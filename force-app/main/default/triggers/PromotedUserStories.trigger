trigger PromotedUserStories on Promoted_User_Story__c(after insert, after delete) {
    // Delegate to handler per trigger framework. No logic here to satisfy PMD AvoidLogicInTrigger.
    fflib_SObjectDomain.triggerHandler(PromotedUserStories.class);
}