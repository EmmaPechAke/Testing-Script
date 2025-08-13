/**
 * @description       : Controller for fetching invoices related to the current user.
 * @author            : Emma Pech
 * @group             : 
 * @last modified on  : 07-31-2025
 * @last modified by  : Horacio Gomez (Saltbox Mgmt)
**/

public without sharing class SaltboxInvoiceController {

    /**
     * @description       : Fetches invoices related to the current user based on their contact or account.
     * @param transactionType : The type of transaction to filter invoices (e.g., 'Invoice').
     * @param orderSummaryId : The ID of the Order Summary to filter invoices.
     * @author            : Emma Pech
     * @group             : 
     * @Last modified on  : 07-31-2025
     * @Last modified by  : Horacio Gomez (Saltbox Mgmt)
     * @return            : List of Transaction_Summary__c records representing invoices.
     * @throws            : None
     */
    @AuraEnabled(cacheable=true)
    public static List<Transaction_Summary__c> getInvoices(String transactionType, String orderSummaryId) {
        User currentUser = [SELECT ContactId, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        Id contactId = currentUser.ContactId;
        Id accountId = currentUser.AccountId;

        return [
            SELECT Id, Transaction_Number__c, Transaction_Status__c, Sent_Date__c, 
                    Transaction_Type__c, Due_Date__c, Link_To_Document_PDF__c, 
                    Order_Summary_Id__c, Order_Summary_Id__r.PoNumber, Invoice_Order_Number__c,
                    Return_Requested__c, Return_Case__c
            FROM Transaction_Summary__c
            WHERE Transaction_Type__c = :transactionType
            AND (
                (Contact__c = :contactId) OR
                (Account__c = :accountId)
            )
            AND Order_Summary_Id__c = :orderSummaryId
            ORDER BY Due_Date__c DESC
        ];
    }
}