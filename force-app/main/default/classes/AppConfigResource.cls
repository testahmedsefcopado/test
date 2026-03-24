/**
 * @description REST resource for managing settings objects.
 * Provides GET, POST, and PATCH operations with built-in security, validation, and auditing.
 *
 * Endpoint: /services/apexrest/api/v1/app-config/*
 */
@SuppressWarnings(
    'PMD.CognitiveComplexity,PMD.StdCyclomaticComplexity,PMD.CyclomaticComplexity,PMD.EagerlyLoadedDescribeSObjectResult,PMD.AvoidDeeplyNestedIfStmts'
)
@RestResource(urlMapping='/api/v1/app-config/*')
global with sharing class AppConfigResource {
    // These objects do not contain any customer or sensitive information.
    private static final Integer MAX_RECORDS_PER_REQUEST = 200;
    private static String namespace = '';

    /**
     * @description Handles GET requests to retrieve records.
     * Requires a 'handshakeId' header for authentication.
     * Supports retrieving a single record by ID or multiple records with filtering.
     * URL format: /api/v1/app-config/{objectApiName}/{recordId} (for single)
     * URL format: /api/v1/app-config/{objectApiName}?field=value (for multiple)
     */
    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String handshakeId = getHeaderIgnoreCase(req, 'handshakeId');
        if (!CodeScanHandshakeService.handshakeCheck(handshakeId)) {
            throw new ApiException(400, Label.Insufficient_Access_Rights);
        }

        if (res == null) {
            res = new RestResponse();
        }
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
            validateSession();
            String objectApiName;
            String recordId = null;
            Map<String, String> pathParts = getPathParts(req.requestURI);
            objectApiName = pathParts.get('objectApiName');
            recordId = pathParts.get('recordId');

            validateSupportedObject(objectApiName);

            if (String.isNotBlank(recordId)) {
                // Single record retrieval
                responseMap.put('data', retrieveSingleRecord(objectApiName, recordId));
            } else {
                // Bulk retrieval with filters
                responseMap.put('data', retrieveMultipleRecords(objectApiName, req.params));
            }
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
        } catch (ApiException ex) {
            handleException(ex, res, responseMap);
        }
    }

    /**
     * @description Handles POST requests to create new records.
     * Requires a 'handshakeId' header for authentication.
     * Supports creating records in bulk.
     */
    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String handshakeId = getHeaderIgnoreCase(req, 'handshakeId');
        if (!CodeScanHandshakeService.handshakeCheck(handshakeId)) {
            throw new ApiException(400, Label.Insufficient_Access_Rights);
        }

        if (res == null) {
            res = new RestResponse();
        }
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
            validateSession();
            String objectApiName = getObjectApiNameFromUri(req.requestURI);
            validateSupportedObject(objectApiName);

            List<SObject> recordsToInsert = parseAndValidateRecords(objectApiName, req.requestBody.toString(), false);

            insert recordsToInsert; //NOPMD

            res.statusCode = 201; // Created
            responseMap.put('message', 'Records created successfully.');
            responseMap.put('recordIds', getRecordIds(recordsToInsert));
            res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
        } catch (ApiException ex) {
            handleException(ex, res, responseMap);
        } catch (DmlException ex) {
            handleException(ex, res, responseMap);
        }
    }

    /**
     * @description Handles PATCH requests to update existing records.
     * Requires a 'handshakeId' header for authentication.
     * Supports updating records in bulk.
     */
    @HttpPatch
    global static void doPatch() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String handshakeId = getHeaderIgnoreCase(req, 'handshakeId');
        if (!CodeScanHandshakeService.handshakeCheck(handshakeId)) {
            throw new ApiException(400, Label.Insufficient_Access_Rights);
        }

        if (res == null) {
            res = new RestResponse();
        }
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
            validateSession();
            String objectApiName = getObjectApiNameFromUri(req.requestURI);
            validateSupportedObject(objectApiName);

            List<SObject> recordsToUpdate = parseAndValidateRecords(objectApiName, req.requestBody.toString(), true);

            update recordsToUpdate; // NOPMD

            res.statusCode = 200; // OK
            responseMap.put('message', 'Records updated successfully.');
            res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
        } catch (ApiException ex) {
            handleException(ex, res, responseMap);
        } catch (DmlException ex) {
            handleException(ex, res, responseMap);
        }
    }

    /**
     * @description Handles DELETE requests to delete records.
     * Supports deleting a single record via URL or multiple via request body.
     * URL single: /api/v1/app-config/{objectApiName}/{recordId}
     * URL bulk:   /api/v1/app-config/{objectApiName}
     * Body can be:
     *   - ["a01...","a01..."] or
     *   - [{"Id": "a01..."}, {"Id": "a01..."}]
     */
    @HttpDelete
    global static void doDelete() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String handshakeId = getHeaderIgnoreCase(req, 'handshakeId');
        if (!CodeScanHandshakeService.handshakeCheck(handshakeId)) {
            throw new ApiException(400, Label.Insufficient_Access_Rights);
        }

        if (res == null) {
            res = new RestResponse();
        }
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
            validateSession();

            String objectApiName;
            String pathRecordId = null;

            // Try full path (object + record Id), fallback to object-only for bulk
            try {
                Map<String, String> pathParts = getPathParts(req.requestURI);
                objectApiName = pathParts.get('objectApiName');
                pathRecordId = pathParts.get('recordId');
            } catch (ApiException e) {
                objectApiName = getObjectApiNameFromUri(req.requestURI);
            }

            validateSupportedObject(objectApiName);

            List<Id> idsToDelete = new List<Id>();
            if (String.isNotBlank(pathRecordId)) {
                idsToDelete.add((Id) pathRecordId);
            } else {
                String body = (req.requestBody != null) ? req.requestBody.toString() : null;
                idsToDelete.addAll(getRecordIdsFromRequest(body));
            }

            if (idsToDelete.isEmpty()) {
                throw new ApiException(400, 'No record Ids provided for deletion.');
            }
            if (idsToDelete.size() > MAX_RECORDS_PER_REQUEST) {
                throw new ApiException(400, 'Request exceeds maximum of ' + MAX_RECORDS_PER_REQUEST + ' records.');
            }

            SObjectType sObjectType = getSObjectType(objectApiName);
            if (sObjectType == null) {
                throw new ApiException(404, 'Object ' + objectApiName + ' not found in the org.');
            }

            List<SObject> toDelete = new List<SObject>();
            for (Id recId : idsToDelete) {
                SObject sob = sObjectType.newSObject();
                sob.put('Id', recId);
                toDelete.add(sob);
            }

            Database.DeleteResult[] results = Database.delete(toDelete, false);

            List<Map<String, Object>> outcomes = new List<Map<String, Object>>();
            for (Integer i = 0; i < results.size(); i++) {
                Database.DeleteResult dr = results[i];
                Map<String, Object> item = new Map<String, Object>();
                item.put('id', toDelete[i].Id);
                item.put('success', dr.isSuccess());
                if (!dr.isSuccess() && dr.getErrors() != null && dr.getErrors().size() > 0) {
                    item.put('error', dr.getErrors()[0].getMessage());
                    item.put('statusCode', dr.getErrors()[0].getStatusCode() != null ? String.valueOf(dr.getErrors()[0].getStatusCode()) : null);
                }
                outcomes.add(item);
            }

            responseMap.put('message', 'Delete operation completed.');
            responseMap.put('results', outcomes);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
        } catch (ApiException ex) {
            handleException(ex, res, responseMap);
        } catch (DmlException ex) {
            handleException(ex, res, responseMap);
        }
    }

    // Private helper methods

    private static SObject retrieveSingleRecord(String objectApiName, String recordId) {
        String query = buildQuery(objectApiName, new Map<String, Object>{ 'Id' => recordId });
        List<SObject> results = Database.query(query); // NOPMD
        if (results.isEmpty()) {
            throw new ApiException(404, objectApiName + ' not found with Id: ' + recordId);
        }
        return results[0];
    }

    private static List<SObject> retrieveMultipleRecords(String objectApiName, Map<String, String> params) {
        String query = buildQuery(objectApiName, (Map<String, Object>) params);
        // The query string is sanitized in buildQuery
        return Database.query(query); // NOPMD
    }

    private static String buildQuery(String objectApiName, Map<String, Object> filters) {
        SObjectType sObjectType = getSObjectType(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        List<String> accessibleFields = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            accessibleFields.add(fieldName);
        }

        String query = 'SELECT ' + String.join(accessibleFields, ',') + ' FROM ' + objectApiName;

        List<String> whereClauses = new List<String>();
        Boolean isHierarchySetting = sObjectType.getDescribe().isCustomSetting() && fieldMap.containsKey('SetupOwnerId');

        if (filters != null) {
            for (String key : filters.keySet()) {
                String filterValue = (String) filters.get(key);

                // Handle special filters for hierarchy custom settings
                if (isHierarchySetting && (key.equalsIgnoreCase('userId') || key.equalsIgnoreCase('profileId')) && String.isNotBlank(filterValue)) {
                    whereClauses.add('SetupOwnerId = \'' + String.escapeSingleQuotes(filterValue) + '\'');

                    // Handle standard field filters
                } else if (fieldMap.containsKey(key) && fieldMap.get(key).getDescribe().isFilterable()) {
                    String fieldNameWithNamespace = addNamespace(key);
                    whereClauses.add(fieldNameWithNamespace + ' = \'' + String.escapeSingleQuotes(filterValue) + '\'');
                }
            }
        }

        // If it's a hierarchy custom setting (identified by having SetupOwnerId) and no specific owner is targeted,
        // default to the organization-level setting.
        if (sObjectType.getDescribe().isCustomSetting() && fieldMap.containsKey('SetupOwnerId') && whereClauses.isEmpty()) {
            // The check for filters is implicit as whereClauses would be populated if userId or profileId were present.
            whereClauses.add('SetupOwnerId = \'' + String.escapeSingleQuotes(UserInfo.getOrganizationId()) + '\'');
        }

        if (!whereClauses.isEmpty()) {
            query += ' WHERE ' + String.join(whereClauses, ' AND ');
        }
        query += ' LIMIT ' + MAX_RECORDS_PER_REQUEST;
        return query;
    }

    private static SObjectType getSObjectType(String objectApiName) {
        return Schema.getGlobalDescribe().get(objectApiName);
    }

    private static List<SObject> parseAndValidateRecords(String objectApiName, String requestBody, Boolean isUpdate) {
        List<Object> untypedRecords;
        try {
            Object parsedJson = JSON.deserializeUntyped(requestBody);
            if (parsedJson instanceof List<Object>) {
                untypedRecords = (List<Object>) parsedJson;
            } else if (parsedJson instanceof Map<String, Object>) {
                untypedRecords = new List<Object>{ (Map<String, Object>) parsedJson };
            } else {
                throw new ApiException(400, 'Invalid JSON format. Expecting an object or an array of objects.');
            }
        } catch (JSONException e) {
            throw new ApiException(400, 'Invalid JSON: ' + e.getMessage());
        }

        if (untypedRecords.size() > MAX_RECORDS_PER_REQUEST) {
            throw new ApiException(400, 'Request exceeds maximum of ' + MAX_RECORDS_PER_REQUEST + ' records.');
        }

        SObjectType sObjectType = getSObjectType(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
        List<SObject> sObjectList = new List<SObject>();

        for (Object untypedRecord : untypedRecords) {
            Map<String, Object> recordMap = (Map<String, Object>) untypedRecord;
            SObject sObj = sObjectType.newSObject();

            if (isUpdate) {
                if (!recordMap.containsKey('Id') || String.isBlank((String) recordMap.get('Id'))) {
                    throw new ApiException(400, 'Record Id is required for update operations.');
                }
                sObj.put('Id', (String) recordMap.get('Id'));
            }

            for (String fieldName : recordMap.keySet()) {
                if (fieldName.equalsIgnoreCase('Id')) {
                    continue;
                }

                String fieldNameWithNamespace = addNamespace(fieldName);
                Schema.SObjectField field = fieldMap.get(fieldNameWithNamespace);
                if (field == null) {
                    throw new ApiException(400, 'Field ' + fieldNameWithNamespace + ' does not exist on ' + objectApiName);
                }

                // Basic type validation could be expanded here
                sObj.put(fieldNameWithNamespace, recordMap.get(fieldName));
            }
            sObjectList.add(sObj);
        }
        return sObjectList;
    }

    private static void validateSession() {
        if (UserInfo.getSessionId() == null) {
            throw new ApiException(401, 'Authentication required. Invalid session token.');
        }
    }

    private static void validateSupportedObject(String objectApiName) {
        initializeNamespace();

        SObjectType sObjectType = getSObjectType(objectApiName);
        if (sObjectType == null) {
            throw new ApiException(404, 'Object ' + objectApiName + ' not found in the org.');
        }

        if (!sObjectType.getDescribe().isCustomSetting()) {
            throw new ApiException(400, 'Object ' + objectApiName + ' is not a Custom Setting and is not supported by this API.');
        }
    }

    private static String getObjectApiNameFromUri(String requestURI) {
        String[] uriParts = requestURI.split('/');
        // For POST/PATCH, the objectApiName is the last part of the URI
        // e.g., /services/apexrest/api/v1/app-config/{objectApiName}
        if (uriParts.size() > 5) {
            return uriParts[uriParts.size() - 1];
        }
        throw new ApiException(400, 'Invalid endpoint URL. Object API name is missing.');
    }

    private static Map<String, String> getPathParts(String requestURI) {
        String[] uriParts = requestURI.split('/');
        // Expected: /services/apexrest/api/v1/app-config/{objectApiName}/{recordId}
        // Index:      0 / 1      / 2    / 3 / 4  / 5                  / 6             / 7
        if (uriParts.size() < 7) {
            throw new ApiException(400, 'Invalid endpoint URL. Object API name is missing.');
        }
        Map<String, String> pathParts = new Map<String, String>();
        pathParts.put('objectApiName', uriParts[6]);
        if (uriParts.size() > 7) {
            pathParts.put('recordId', uriParts[7]);
        } else {
            pathParts.put('recordId', null);
        }
        return pathParts;
    }

    private static List<Id> getRecordIds(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject record : records) {
            ids.add(record.Id);
        }
        return ids;
    }

    private static void initializeNamespace() {
        if (String.isBlank(namespace)) {
            String className = AppConfigResource.class.getName();
            if (className.contains('.')) {
                namespace = className.substring(0, className.indexOf('.')) + '__';
            }
        }
    }

    private static String addNamespace(String fieldOrObjectName) {
        initializeNamespace();
        if (String.isNotBlank(namespace) && !fieldOrObjectName.startsWith(namespace) && fieldOrObjectName.endsWith('__c')) {
            return namespace + fieldOrObjectName;
        }
        return fieldOrObjectName;
    }

    private static String getHeaderIgnoreCase(RestRequest req, String targetHeaderName) {
        if (req == null || req.headers == null) {
            return null;
        }
        for (String key : req.headers.keySet()) {
            if (key != null && key.equalsIgnoreCase(targetHeaderName)) {
                return req.headers.get(key);
            }
        }
        return null; // Not found
    }

    private static void handleException(Exception ex, RestResponse res, Map<String, Object> responseMap) {
        if (ex instanceof ApiException) {
            ApiException apiEx = (ApiException) ex;
            res.statusCode = apiEx.statusCode;
            responseMap.put('error', apiEx.getMessage());
        } else if (ex instanceof DmlException) {
            DmlException dmlEx = (DmlException) ex;
            res.statusCode = 400;
            responseMap.put('error', 'DML Error: ' + dmlEx.getDmlMessage(0));
        } else {
            res.statusCode = 500;
            responseMap.put('error', 'An unexpected error occurred: ' + ex.getMessage());
        }
        res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
    }

    // Parse Ids for bulk delete requests
    private static List<Id> getRecordIdsFromRequest(String requestBody) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(requestBody)) {
            return ids;
        }
        try {
            Object parsed = JSON.deserializeUntyped(requestBody);
            if (parsed instanceof List<Object>) {
                for (Object o : (List<Object>) parsed) {
                    if (o instanceof String) {
                        ids.add((Id) (String) o);
                    } else if (o instanceof Map<String, Object>) {
                        Map<String, Object> rec = (Map<String, Object>) o;
                        if (rec.containsKey('Id') && !String.isBlank((String) rec.get('Id'))) {
                            ids.add((Id) (String) rec.get('Id'));
                        }
                    }
                }
            } else if (parsed instanceof Map<String, Object>) {
                Map<String, Object> rec = (Map<String, Object>) parsed;
                if (rec.containsKey('Id') && !String.isBlank((String) rec.get('Id'))) {
                    ids.add((Id) (String) rec.get('Id'));
                }
            } else {
                throw new ApiException(400, 'Invalid JSON format for delete. Expecting an array of Ids or objects with Id.');
            }
        } catch (JSONException e) {
            throw new ApiException(400, 'Invalid JSON: ' + e.getMessage());
        }
        return ids;
    }

    /**
     * @description Custom exception class for handling API-specific errors.
     */
    public class ApiException extends Exception {
        public Integer statusCode;

        public ApiException(Integer statusCode, String message) {
            this.setMessage(message);
            this.statusCode = statusCode;
        }
    }
}