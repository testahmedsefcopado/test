@isTest
public with sharing class PostInstallClassTest {
    
    @TestSetup
    static void makeData() {
        User usr1 = TestDataFactory.createUser('System Administrator');
        usr1.username = Crypto.getRandomLong() + '@' + Crypto.getRandomLong() + '.Test1';
        User usr2 = TestDataFactory.createUser('Standard User');
        usr2.username = Crypto.getRandomLong() + '@' + Crypto.getRandomLong() + '.Test2';
        insert new List<User>{ usr1, usr2 };
    }

    @isTest 
    public static void createCrtAccessPermissionSetPass() {
        
        //Exercise
        Test.startTest();
        User sysAdmin = [SELECT id FROM User WHERE username LIKE '%Test1'];
        System.runAs(sysAdmin) {
            PostInstallClass myClass = new PostInstallClass();
            Test.testInstall(myClass, null);
        }
        Test.stopTest();

        //Verify
        List<PermissionSet> permissionSet = [SELECT Id, Name FROM PermissionSet WHERE Name = 'CRT_Access_Test' WITH USER_MODE LIMIT 1];

        List<ObjectPermissions> objectPermissions = [
            SELECT PermissionsRead
            FROM ObjectPermissions
            WHERE Parent.Name = :permissionSet[0].Name AND SObjectType = 'UserExternalCredential'
        ];
        System.assertEquals(false, permissionSet.isEmpty(), 'Permission should be inserted successfully');
        System.assertEquals(true, objectPermissions[0].PermissionsRead, 'Read permission should be inserted successfully');
    }

    @isTest
    public static void createCrtAccessPermissionSetFail() {
        Test.startTest();
        User stdUsr = [SELECT id FROM User WHERE username LIKE '%Test2'];

        System.runAs(stdUsr) {
            PostInstallClass myClass = new PostInstallClass();
            Test.testInstall(myClass, null);
        }

        Test.stopTest();

        List<PermissionSet> permissionSet = [SELECT Id, Name FROM PermissionSet WHERE Name = 'CRT_Access_Test' WITH USER_MODE LIMIT 1];
        System.assertEquals(true, permissionSet.isEmpty(), 'Standard User should not have permission to insert a Permission Set');
    }
}