public class BadPMDExample {

    public void doStuff(List<Id> accountIds) {
        // Unused variable
        Integer counter = 0;

        // Magic number
        if(accountIds.size() > 5) {
            System.debug('Too many IDs');
        }

        // Hard-coded string literal multiple times
        String status = 'Active';
        for(Id accId : accountIds) {
            // SOQL inside a loop (bad)
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accId];
            if(acc.Name == 'Test') {
                acc.Name = 'Updated';
                update acc;
            }
        }

        // Poor naming convention
        String s = 'Done';

        // Long method with multiple responsibilities
        try {
            Integer x = 10;
            if(x == 10) {
                x = 20;
            }
            System.debug('Value: ' + x);
        } catch(Exception e) {
            // Empty catch block
        }
    }

    void helper() {
        // Method without access modifier
        System.debug('Helper method');
    }
}