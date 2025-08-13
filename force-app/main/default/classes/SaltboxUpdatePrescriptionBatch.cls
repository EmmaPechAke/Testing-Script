/**
 * @description        : Batch class to process 'Header Updates' from Order_Change_Prescription__c records.
 * @author             : Emma Pech
 * @last modified on   : 06-27-2025
 * @last modified by   : Emma Pech | emmanuel@saltboxmgmt.com
 */
global class SaltboxUpdatePrescriptionBatch implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * @description Returns records to process (New Header Update prescriptions).
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Prescription_Payload__c, Related_Order_Summary_Id__c, Status__c
            FROM Order_Change_Prescription__c
            WHERE Change_Type__c = 'Header Updates'
              AND Status__c = 'New'
        ]);
    }

    /**
     * @description Processes each prescription, applies updates, logs errors if any.
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<ProcessException> exceptionsToInsert = new List<ProcessException>();

        for (Order_Change_Prescription__c prescription : (List<Order_Change_Prescription__c>) scope) {
            try {
                processPrescription(prescription);
                prescription.Status__c = 'Completed';
                prescription.Error_Message__c = null;
            } catch (Exception ex) {
                prescription.Status__c = 'Error';
                prescription.Error_Message__c = ex.getMessage();

                // Log error as a ProcessException
                ProcessException exc = new ProcessException(
                    AttachedToId = prescription.Id,
                    Message = ex.getMessage()
                );
                
                exceptionsToInsert.add(exc);
            }
        }

        if(exceptionsToInsert.size() > 0) {
            insert exceptionsToInsert;
        }
        
        update scope;
    }

    global void finish(Database.BatchableContext bc) {
        // Optional: Send notification, logging, etc.
    }

    /**
     * @description Applies payload updates to OrderSummary and OrderDeliveryGroupSummary.
     */
    private void processPrescription(Order_Change_Prescription__c presc) {
        if (String.isBlank(presc.Prescription_Payload__c)) return;

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(presc.Prescription_Payload__c);

        Id orderSummaryId = presc.Related_Order_Summary_Id__c;
        OrderSummary orderSummary = [SELECT Id, AccountId, OrderedDate, PoNumber FROM OrderSummary WHERE Id = :orderSummaryId LIMIT 1];

        String salesOrderNumber = (String)payload.get('orderId');
        OrderDeliveryGroupSummary deliveryGroup = [
            SELECT Id, Sales_Order_Number__c, DeliverToStreet,
                   DeliverToCity, DeliverToState, DeliverToStateCode, DeliverToPostalCode,
                   DeliverToCountry, Status__c
            FROM OrderDeliveryGroupSummary 
            WHERE Sales_Order_Number__c = :salesOrderNumber
            LIMIT 1
        ];

        List<String> changeLog = new List<String>();

        // Update delivery group fields
        updateFieldIfDifferent(deliveryGroup, 'DeliverToStreet', (String)payload.get('shipToAddress1'), changeLog);
        updateFieldIfDifferent(deliveryGroup, 'DeliverToCity', (String)payload.get('shipToCity'), changeLog);
        updateFieldIfDifferent(deliveryGroup, 'DeliverToStateCode', (String)payload.get('shipToState'), changeLog);
        updateFieldIfDifferent(deliveryGroup, 'DeliverToPostalCode', (String)payload.get('shipToZip'), changeLog);
        updateFieldIfDifferent(deliveryGroup, 'DeliverToCountry', (String)payload.get('shipToCountry'), changeLog);
        updateFieldIfDifferent(deliveryGroup, 'Status__c', (String)payload.get('orderStatus'), changeLog);

        // Update order summary fields
        updateFieldIfDifferent(orderSummary, 'AccountId', (String)payload.get('customerId'), changeLog);
        updateFieldIfDifferent(orderSummary, 'OrderedDate', (Date)payload.get('dateCreated'), changeLog);
        updateFieldIfDifferent(orderSummary, 'PoNumber', (String)payload.get('poNumber'), changeLog);

        update orderSummary;
        update deliveryGroup;

        if (!changeLog.isEmpty()) {
            String message = 'Header Update Processed. Changes fields:\n- ' + String.join(changeLog, '\n- ');
            postChatter(orderSummary.Id, message);
            // postChatter(deliveryGroup.Id, message);
        }
    }

    /**
     * @description Updates a field if the value has changed, logs the change.
     */
    private void updateFieldIfDifferent(SObject sObj, String fieldName, Object newValue, List<String> changeLog) {
        Object currentValue = sObj.get(fieldName);
        if (newValue != null && currentValue != newValue) {
            sObj.put(fieldName, newValue);
            changeLog.add(fieldName + ' changed to: ' + String.valueOf(newValue));
        }
    }

    /**
     * @description Posts a Chatter message on the given record.
     */
    private void postChatter(Id parentId, String message) {
        FeedItem post = new FeedItem();
        post.ParentId = parentId;
        post.Body = message;
        insert post;
    }
}