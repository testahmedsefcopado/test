public with sharing class PullRequestHandler {
    @InvocableMethod(label='Pull Request Test Record Management' category='Pull Request')
    public static List<String> execute(List<Request> requests) {
        List<String> result = new List<String>();
        Request request = requests[0];
        Boolean isPromotion = isPromotion(request);
        List<String> userStoryIds = request.getStoryIds();
        List<String> usIdsWithMetaData = hasMetadata(userStoryIds);

        if (userStoryIds.isEmpty()) {
            result.add(Label.No_User_Story);
        } else if (!usIdsWithMetaData.isEmpty()) {
            if(isPromotion){
                result.addAll(processPromotion(request));
            } else {
                try {
                    result.addAll(processUserStories(usIdsWithMetaData, request));
                } catch (Exception ex) {
                    result.add(ex.getMessage() + ex.getStackTraceString());
                }
            }
        }
        return result;
    }

    /**
        Pull Request jobStep is generated as a part of SFDX Deploy template when its generated for before deploy 
        hence we are looking for an in progress one to identify if this is a User story or Promotion one
    */
    private static Boolean isPromotion(Request request){
        String promotionId = request.get15charsPromotionId();

        if (String.isBlank(promotionId)) {
            return false;
        }

        Integer jobCount = [SELECT COUNT() FROM copado__JobExecution__c WHERE copado__Context__c LIKE : '%' + promotionId + '%' AND copado__Status__c = 'In Progress' AND copado__Template__r.Name = 'SFDX Deploy' WITH USER_MODE];
        return jobCount > 0;
    }

    private static List<String> processPromotion(Request request) {
        List<String> result = new List<String>();
        Boolean hasPromotionPr = hasPromotionPr(request.promotionId);
        Boolean promotionPrApproved = promotionPrApproved(request.promotionId);
        if(!hasPromotionPr){
            result.add(Label.Promotion_Missing_PR);
        } else if(!promotionPrApproved){
            result.add(Label.Promotion_PR_Missing_Approval);
        }
        return result;
    }

    @SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
    private static List<String> processUserStories(List<String> userStoryIds, Request request) {
        List<String> result = new List<String>();
        Map<Id, copado__Pull_Request__c> prByUserStory = getPullRequestsByUserStory(userStoryIds);
        List<copado__User_Story__c> userStories = getUserStories(userStoryIds);
        List<String> prMissingUserStories = new List<String>();
        List<String> prNotApprovedUserStories = new List<String>();

        for (copado__User_Story__c userStory : userStories) {
            Boolean hasPR = prByUserStory.containsKey(userStory.Id);
            Boolean isApproved = userStory.copado__Pull_Requests_Approved__c;

            if (!hasPR || !isApproved) {
                if (null == request.promotionId) {
                    String label = !hasPR ? Label.PR_Missing : Label.PR_Not_Approved;
                    result.add(label + ' (' + userStory.Name + ')');
                } else {
                    if (!hasPR) {
                        prMissingUserStories.add(userStory.Name);
                    }
                    if (hasPR && !isApproved) {
                        prNotApprovedUserStories.add(userStory.Name);
                    }
                }
            }
        }

        String failureMsg = getFailedUserStoriesMessages(prMissingUserStories, prNotApprovedUserStories);
        if (String.isNotBlank(failureMsg)) {
            result.add(failureMsg);
        }

        return result;
    }

    private static String getFailedUserStoriesMessages(List<String> prMissingUserStories, List<String> prNotApprovedUserStories) {
        String failureMsg = '';
        if (!prMissingUserStories.isEmpty()) {
            failureMsg += buildFailedUserStoriesMessage(prMissingUserStories, Label.Promotion_PR_Missing);
        }
        if (!prNotApprovedUserStories.isEmpty()) {
            failureMsg += buildFailedUserStoriesMessage(prNotApprovedUserStories, Label.Promotion_PR_Not_Approved);
        }

        if ((prMissingUserStories.size() + prNotApprovedUserStories.size()) == 1) {
            failureMsg = failureMsg.remove(';');
        }

        return failureMsg;
    }

    private static String buildFailedUserStoriesMessage(List<String> failedUserStories, String failureMsg) {
        String message = failureMsg;
        for (Integer i = 0; i < failedUserStories.size(); i++) {
            message += ' ' + failedUserStories[i];
            if (i < failedUserStories.size() - 1) {
                message += ',\n';
            } else {
                message += ';\n';
            }
        }
        return message;
    }

    private static Boolean hasPromotionPr(String promotionId) {
        return ![SELECT Id FROM copado__Promotion_Pull_Request__c WHERE copado__Promotion__c = : promotionId WITH USER_MODE].isEmpty();
    }

    private static Map<Id, copado__Pull_Request__c> getPullRequestsByUserStory(List<String> userStoryIds) {
        Map<Id, copado__Pull_Request__c> prByUserStory = new Map<Id, copado__Pull_Request__c>();
        for (copado__Pull_Request__c pr : [
            SELECT Id, copado__User_Story__c
            FROM copado__Pull_Request__c
            WHERE copado__User_Story__c IN :userStoryIds
            WITH USER_MODE
        ]) {
            prByUserStory.put(pr.copado__User_Story__c, pr);
        }
        return prByUserStory;
    }

    private static Boolean promotionPrApproved(String promotionId) {
        return [
            SELECT Id, Name, copado__Pull_Requests_Approved__c
            FROM copado__Promotion__c
            WHERE Id = :promotionId
            WITH USER_MODE LIMIT 1
        ].copado__Pull_Requests_Approved__c;
    }

    private static List<copado__User_Story__c> getUserStories(List<String> userStoryIds) {
        return [
            SELECT Id, Name, copado__Pull_Requests_Approved__c
            FROM copado__User_Story__c
            WHERE Id IN :userStoryIds
            WITH USER_MODE
        ];
    }

    private static List<String> hasMetadata(List<String> ids) {
        List<String> hasMetadata = new List<String>();
        Map<Id, Id> parentByContentDocId = new Map<Id, Id>();
        if(!ids.isEmpty()){
            for (ContentDocumentLink link : [
                SELECT Id, LinkedEntityId, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :ids AND ContentDocument.Title = 'Copado Commit changes'
                WITH USER_MODE
            ]) {
                parentByContentDocId.put(link.ContentDocumentId, link.LinkedEntityId);
            }

            for (ContentVersion version : [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :parentByContentDocId.keyset() AND ContentSize > 0
                WITH USER_MODE
            ]) {
                hasMetadata.add(parentByContentDocId.get(version.ContentDocumentId));
            }
        }
        return hasMetadata;
    }

    public inherited sharing class Request {
        @InvocableVariable(label='User Story Id' required=false)
        public String userStoryId;
        @InvocableVariable(label='Promotion Id' required=false)
        public String promotionId;

        private List<String> getStoryIds() {
            List<Id> userStoryIds = new List<Id>();
            for (copado__Promoted_User_Story__c promotedStory : [
                SELECT Id, copado__User_Story__c
                FROM copado__Promoted_User_Story__c
                WHERE copado__Promotion__c = :promotionId
                WITH USER_MODE
            ]) {
                userStoryIds.add(promotedStory.copado__User_Story__c);
            }
            return (null != this.userStoryId ? new List<String>{ this.userStoryId } : userStoryIds);
        }

        private String get15charsPromotionId(){
            return null != this.promotionId ? this.promotionId.subString(0,15) : '';
        }        
    }   
}