public inherited sharing class PromoteDeployQueueable implements Finalizer, Queueable {
    private Actions.PromotionRequest request;
    private Actions.PromotionResult response;
    private static final String PROMOTION_CREATION_FAILED_EMAIL_NOTIFICATION = 'Failed_Promotion_Creation';
    private static final String PROMOTION_CREATION_FAILED_CUSTOM_NOTIFICATION_TYPE = 'SFP_Promote_And_Deploy_Failure_Notification';
    private static final String BASE_URL = URL.getOrgDomainUrl().toExternalForm();

    // PUBLIC

    public PromoteDeployQueueable(Actions.PromotionRequest request) {
        this.request = request;
    }

    public void execute() {
        AsyncOptions options = new AsyncOptions();
        options.DuplicateSignature = QueueableDuplicateSignature.Builder()
            .addInteger(System.hashCode(request.userStoryIds))
            .addId([SELECT Id FROM ApexClass WHERE Name = 'PromoteDeployQueueable'].Id)
            .build();
        System.enqueueJob(this, options);
    }

    public void execute(QueueableContext ctx) {
        String jobId = '' + ctx.getJobId();
        System.attachFinalizer(this);

        try {
            response = Actions.PromotionService.execute(request);

            updatePromotionsToInProgress(response);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error executing the job [' + jobId + ']: ' + ex.getMessage() + ' StackTrace: ' + ex.getStackTraceString());//NOPMD
            sendErrorNotification(ex.getMessage());
        } finally {
            System.debug(LoggingLevel.DEBUG,'Completed: execution of queueable job: ' + jobId);//NOPMD
        }
    }

    public void execute(FinalizerContext ctx) {
        String parentJobId = ctx.getAsyncApexJobId();

        if (ctx.getResult() == ParentJobResult.SUCCESS) {
            System.debug(LoggingLevel.DEBUG,'Parent queueable job [' + parentJobId + '] completed successfully.');//NOPMD
        } else {
            System.debug(LoggingLevel.ERROR, 'Parent queueable job [' + parentJobId + '] failed due to unhandled exception: ' + ctx.getException().getMessage());//NOPMD
            sendErrorNotification(ctx.getException().getMessage());
        }
    }

    @TestVisible
    private void updatePromotionsToInProgress(Actions.PromotionResult response) {
        Set<Id> completedPromotionIdsForReset = new Set<Id>();
        Set<String> completedStatuses = new Set<String>{
            PromotionConstants.STATUS_COMPLETED,
            PromotionConstants.STATUS_COMPLETED_SUCCESSFULLY,
            PromotionConstants.STATUS_COMPLETED_WITH_ERRORS,
            PromotionConstants.STATUS_VALIDATED,
            PromotionConstants.STATUS_VALIDATION_FAILED,
            PromotionConstants.STATUS_CANCELLED
        };
        if (response == null) {
            return;
        }

        List<Promotion__c> promotions = new List<Promotion__c>();

        if (response.promotion != null) {
            Promotion__c promotionToCheck = new PromotionsSelector().byIds(new Set<Id>{ response.promotion.Id }).get(0);
            if (!completedStatuses.contains(promotionToCheck.Status__c)) {
                promotions.add(new Promotion__c(Id = response.promotion.Id, Status__c = PromotionConstants.STATUS_IN_PROGRESS));
            } else if (completedStatuses.contains(promotionToCheck.Status__c)) {
                completedPromotionIdsForReset.add(response.promotion.Id);
            }
        }
        // Reset User Story checkboxes(Ready To Promote, Promote and Deploy) and Update Target Environment on User Story 
        // once promotion is completed when skipped deployment steps deployed only.
        if (!completedPromotionIdsForReset.isEmpty()) {
            PromotionTriggerHelper.prepareData(new List<Promotion__c>{ response.promotion }, new List<Promotion__c>());
            PromotionTriggerHelper.completedPromotionIds.addAll(completedPromotionIdsForReset);
            PromotionTriggerHelper.resetUserStories();
        }

        if (!promotions.isEmpty()) {
            PromotionTriggerHelper.bypassPromotionTrigger = true;
            DML.safeUpdate(
                promotions,
                String.format(
                    Label.ErrorWhileUpdating,
                    new List<String>{
                        Promotion__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFAULT).getLabel(),
                        'PromoteDeployQueueable.updatePromotionsToInProgress'
                    }
                )
            );
            PromotionTriggerHelper.bypassPromotionTrigger = false;
        }
    }

    private void sendErrorNotification(String message) {
        List<User_Story__c> userStories = [
            SELECT Id, Name, Promote_and_Deploy__c
            FROM User_Story__c
            WHERE Id = :this.request.userStoryIds[0]
            WITH USER_MODE
            LIMIT 1
        ];
        String userStoryName = !userStories.isEmpty() ? userStories[0].Name : '';

        updateUserStories(userStories);

        // Sending both way just in case user miss one of them
        sendCustomNotification(userStoryName, message);
        sendEmailNotification(userStoryName, message);
    }

    private void sendCustomNotification(String userStoryName, String message) {
        CustomNotificationType cnType = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :PROMOTION_CREATION_FAILED_CUSTOM_NOTIFICATION_TYPE
        ];
        Id userId = Userinfo.getUserId();
        String recordId = this.request.userStoryIds[0];
        Messaging.CustomNotification customNotificationObj = new Messaging.CustomNotification();
        customNotificationObj.setBody(message);
        customNotificationObj.setTitle(String.format(Label.PROMOTION_CREATION_FAILED_NOTIFICATION_TITLE, new List<String>{ userStoryName }));
        customNotificationObj.setNotificationTypeId(cnType.id);
        customNotificationObj.setSenderId(Userinfo.getUserId());
        customNotificationObj.setTargetId(recordId);

        try {
            customNotificationObj.send(new Set<String>{ userId });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'Problem sending notification: ' + e.getMessage());//NOPMD
        }
    }

    private void sendEmailNotification(String userStoryName, String message) {
        CopadoNotifications.SendRequest request = new CopadoNotifications.SendRequest();
        request.name = PROMOTION_CREATION_FAILED_EMAIL_NOTIFICATION;
        request.recipientIds = new Set<Id>{ UserInfo.getUserId() };
        request.mergeData = getMergeData(userStoryName, message);

        CopadoNotifications.send(request);
    }

    private Map<String, String> getMergeData(String userStoryName, String message) {
        Map<String, String> mergeData = new Map<String, String>{
            'UserName' => UserInfo.getName(),
            'UserStoryName' => userStoryName,
            'UserStoryLink' => BASE_URL +
            '/' +
            this.request.userStoryIds[0],
            'PromotionCreationError' => message
        };

        return mergeData;
    }

    private void updateUserStories(List<User_Story__c> records) {
        List<User_Story__c> userStoriestoBeUpdated = new List<User_Story__c>();
        for (User_Story__c userStory : records) {
            if (userStory.Promote_and_Deploy__c) {
                userStoriestoBeUpdated.add(new User_Story__c(Id = userStory.Id, Promote_and_Deploy__c = false));
            }
        }

        if (!userStoriestoBeUpdated.isEmpty()) {
            UserStories.bypassTrigger = true;
            DML.safeUpdate(
                userStoriestoBeUpdated,
                String.format(
                    Label.ErrorWhileUpdating,
                    new List<String>{
                        User_Story__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFAULT).getLabel(),
                        'PromoteDeployQueueable.updateUserStories'
                    }
                )
            );
            UserStories.bypassTrigger = false;
        }
    }
}