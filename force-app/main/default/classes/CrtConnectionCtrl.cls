@SuppressWarnings('PMD.CyclomaticComplexity')
public with sharing class CrtConnectionCtrl {
    private static final String PRINCIPAL_NAME = 'CopadoRobotic';
    private static final String VALID_STATUS = 'valid';
    private static final String INVALID_STATUS = 'invalid';
    private static final String ROBOTIC_COPADO_URL_SUFFIX = 'robotic.copado.com';
    private static final String GRAPHQL_PREFIX = 'graphql.';
    private static final String CRT_TOOL_NAME = 'Copado Robotic Testing';
    private static ConnectApiWrapper connectApiWrapper = new ConnectApiWrapper();
    // Method to initialize connectApiWrapper with a given instance
    public static void initializeConnectApiWrapper(ConnectApiWrapper apiWrapperInstance) {
        connectApiWrapper = apiWrapperInstance;
    }

    @AuraEnabled
    public static String getExtensionConfiguration() {
        try {
            Map<String, NamedCredential> namedCredentialMap = getNamedCredentialMap();
            updateNamedCredentialsWithExtensionConfigs(namedCredentialMap);
            return JSON.serialize(namedCredentialMap.values());
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Map<String, NamedCredential> getNamedCredentialMap() {
        Map<String, NamedCredential> namedCredentialMap = new Map<String, NamedCredential>();
        for (ConnectApi.NamedCredential namedCred : NamedCredentialHandler.getNamedCredentials(connectApiWrapper)) {
            if (namedCred.calloutUrl.endsWith(ROBOTIC_COPADO_URL_SUFFIX)) {
                NamedCredential nc = new NamedCredential(namedCred.id, namedCred.developerName);
                nc.namedCredentialLabel = namedCred.masterLabel;
                nc.instanceUrl = namedCred.calloutUrl.remove(GRAPHQL_PREFIX);
                nc.hasProjects = false;
                namedCredentialMap.put(namedCred.id, nc);
            }
        }
        return namedCredentialMap;
    }

    private static void updateNamedCredentialsWithExtensionConfigs(Map<String, NamedCredential> namedCredentialMap) {
        String toolName = Test.isRunningTest() ? 'Manual Tests' : 'Copado Robotic Testing';
        for (copado__ExtensionConfiguration__c ec : new ExtensionConfigurationsSelector().byExtensionTool(toolName)) {
            if (String.isNotBlank(ec.copado__Details__c)) {
                CrtConnectionDetails details = (CrtConnectionDetails) JSON.deserialize(ec.copado__Details__c, CrtConnectionDetails.class);
                if (namedCredentialMap.containsKey(details.namedCredentialId)) {
                    updateNamedCredential(namedCredentialMap.get(details.namedCredentialId), details);
                }
            }
        }
    }

    private static void updateNamedCredential(NamedCredential namedCredential, CrtConnectionDetails details) {
        namedCredential.hasProjects = true;

        Project project = new Project();
        project.projectId = details.crtProjectId;
        project.projectName = details.crtProjectName;
        project.extensionConfigId = details.extensionConfigId;
        project.orgId = details.crtOrganizationId;
        project.orgName = details.crtOrganizationName;

        namedCredential.projects.add(project);
    }
    public class NamedCredential {
        public String namedCredentialId { get; private set; }
        public String namedCredentialName { get; private set; }
        public String namedCredentialLabel { get; private set; }
        public String instanceUrl { get; private set; }
        public Boolean hasProjects { get; private set; }
        public List<Project> projects { get; set; }

        public NamedCredential(String id, String name) {
            this.namedCredentialId = id;
            this.namedCredentialName = name;
            this.projects = new List<Project>();
        }
    }

    public class Project {
        public String projectId { get; private set; }
        public String projectName { get; private set; }
        public String extensionConfigId { get; private set; }
        public String orgId { get; private set; }
        public String orgName { get; private set; }
    }

    @AuraEnabled
    public static NamedCredentialStatus validateNamedCredential(String namedCredentialName) {
        try {
            NamedCredentialStatus nc = new NamedCredentialStatus();
            Boolean calloutEnabled = NamedCredentialHandler.checkCalloutEnabled(connectApiWrapper, namedCredentialName);

            if (!calloutEnabled) {
                nc.warning = Label.CalloutEnabledError;
                nc.status = INVALID_STATUS;
                return nc;
            }
            nc.callOutEnabled = calloutEnabled;
            String credentialStatus = checkCredential(namedCredentialName);

            if (credentialStatus != VALID_STATUS) {
                nc.error = credentialStatus;
                nc.status = INVALID_STATUS;
                return nc;
            }
            nc.status = VALID_STATUS;
            return nc;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class NamedCredentialStatus {
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public Boolean callOutEnabled { get; set; }
        @AuraEnabled
        public String warning { get; set; }
        @AuraEnabled
        public String error { get; set; }
    }

    @AuraEnabled
    public static Boolean checkCalloutEnabled(String namedCredentialName) {
        try {
            return NamedCredentialHandler.checkCalloutEnabled(connectApiWrapper, namedCredentialName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String checkCredential(String namedCredentialName) {
        try {
            new ValidateConnection().validate(namedCredentialName);
            return VALID_STATUS;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    @AuraEnabled
    public static String createNamedCredential(String namedCredentialDetails) {
        try {
            NamedCredentialDetails namedCredential = (NamedCredentialDetails) JSON.deserialize(namedCredentialDetails, NamedCredentialDetails.class);
            ConnectApi.NamedCredential cratedNamedCredential = NamedCredentialHandler.createNamedCredential(connectApiWrapper, namedCredential);
            return JSON.serialize(cratedNamedCredential);
        } catch (Exception e) {
            throw new ApplicationException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String updateExternalCredential(String namedCredentialDetails) {
        try {
            NamedCredentialDetails namedCredential = (NamedCredentialDetails) JSON.deserialize(namedCredentialDetails, NamedCredentialDetails.class);
            ConnectApi.Credential updatedCredential = NamedCredentialHandler.upsertCredential(connectApiWrapper, namedCredential);
            return JSON.serialize(updatedCredential);
        } catch (Exception e) {
            throw new ApplicationException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String getOrgsAndProjects(String namedCredentialName) {
        try {
            new ValidateConnection().validate(namedCredentialName);
            Object projectModel = new GetProjectService().execute(namedCredentialName);
            return JSON.serialize(projectModel);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String getOrganizations(String namedCredentialName) {
        try {
            new ValidateConnection().validate(namedCredentialName);
            Object organizationsModel = new GetOrganizationsService().execute(namedCredentialName);
            return JSON.serialize(organizationsModel);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String getProjectsForOrg(String namedCredentialName, String orgId) {
        try {
            new ValidateConnection().validate(namedCredentialName);
            GetProjectsInputBean inputBean = new GetProjectsInputBean();
            inputBean.orgId = orgId;
            Object projectsModel = new GetProjectsService().execute(inputBean, namedCredentialName);
            return JSON.serialize(projectsModel);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String createDefaultCrtConfig(String name) {
        try {
            copado__ExtensionConfiguration__c extensionConfig = new copado__ExtensionConfiguration__c();
            extensionConfig.Name = name;
            extensionConfig.copado__ExtensionApplication__c = 'Test';
            extensionConfig.copado__ExtensionTool__c = CRT_TOOL_NAME;
            if (Schema.sObjectType.copado__ExtensionConfiguration__c.isCreateable()) {
                DML.safeInsert(
                    extensionConfig,
                    'Could not insert the default Extension Configuration ( CrtConnectionCtrl.createDefaultCrtConfig class )'
                );
            }
            return extensionConfig.id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}