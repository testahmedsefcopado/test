public without sharing class PostInstallClass implements InstallHandler {
    private static final String PERMISSION_SET_LABEL = 'CRT Access' + (Test.isRunningTest() ? ' Test' : '');
    private static final String PERMISSION_SET_NAME = 'CRT_Access' + (Test.isRunningTest() ? '_Test' : '');
    private static final String PERMISSION_SET_GROUP_NAME = 'Copado_Explorer_User';
    private static final String PERMISSION_SET_DESCRIPTION = 'This permission set provide access to Copado Robotic Testing secured named credentials';

    private static PermissionSet permissionSet;

    //FALSE POSITIVE : Using SECURITY_ENFORCED instead of USER_MODE since user mode fails in this context
    private static List<PermissionSetGroup> permissionGroups { 
        get {
            if(null == permissionGroups){
                permissionGroups = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :PERMISSION_SET_GROUP_NAME AND NamespacePrefix = :Settings.NAMESPACE WITH SECURITY_ENFORCED LIMIT 1];
            }
            return permissionGroups;
        } private set;
    }

    private static List<PermissionSet> existingPermissionSet { 
        get {
            if(null == existingPermissionSet){
                existingPermissionSet = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME WITH SECURITY_ENFORCED LIMIT 1];
            }
            return existingPermissionSet;
        } private set;
    }

    private static Boolean hasPsgAssignment(){
        Boolean hasAssignment = false;
        if(!existingPermissionSet.isEmpty()){
            Id permSetId = permissionSetId(permissionSet);
            List<PermissionSetGroupComponent> groups = [SELECT Id FROM PermissionSetGroupComponent WHERE PermissionSetGroup.DeveloperName = : PERMISSION_SET_GROUP_NAME AND PermissionSet.Id = :permSetId WITH SECURITY_ENFORCED LIMIT 1];
            hasAssignment = !groups.isEmpty() ? true : false;
        }
        return hasAssignment;
    }
    
    //InstallHandler method
    public void onInstall(InstallContext context) {
        createCrtAccessPermissionSet(context.installerID());
    }

    //helper methods
    private static void createCrtAccessPermissionSet(Id userId) {
        try {
            if (existingPermissionSet.isEmpty() || Test.isRunningTest()) {
                // Create a new Permission Set
                if (!Schema.sObjectType.PermissionSet.isCreateable() || !Schema.sObjectType.ObjectPermissions.isCreateable()) {
                    throw new ApplicationException(Label.External_Permission_Set_Error);
                }
                permissionSet = new PermissionSet();
                permissionSet.Label = PERMISSION_SET_LABEL;
                permissionSet.Name = PERMISSION_SET_NAME;
                permissionSet.Description = PERMISSION_SET_DESCRIPTION ;

                insert permissionSet;

                ObjectPermissions objectPermission = new ObjectPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'UserExternalCredential',
                    PermissionsRead = true
                );
                insert objectPermission;
            }
            if(!hasPsgAssignment()){
                insert new PermissionSetGroupComponent(
                    PermissionSetGroupId = permissionGroups[0].Id,
                    PermissionSetId = permissionSetId(permissionSet)
                );
            }
            
        } catch (Exception exp) {
            sendExceptionEmail(userId, exp.getMessage());
        }
    }

    private static Id permissionSetId(PermissionSet permissionSet){
        return !existingPermissionSet.isEmpty() ? existingPermissionSet[0].Id : permissionSet.Id;
    }

    private static void sendExceptionEmail(Id userId, String exceptionMessage){
        User user = [SELECT Id, Email FROM User WHERE Id = :userId WITH SECURITY_ENFORCED];
        String toAddress = user.Email;
        String[] toAddresses = new List<String>{ toAddress };
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSenderDisplayName('My Package Support');
        email.setSubject('Permission set/group creation failed');
        email.setPlainTextBody('Please check the error : ' + exceptionMessage);
        Messaging.sendEmail(new List<Messaging.Email>{ email });
    }
}