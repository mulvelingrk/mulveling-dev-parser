/*
 * Mike Ulveling
 * 
 * !! See here for documention of usage and features:
 * https://jira-stars.atlassian.net/wiki/spaces/~557058059effa53d514c58a5b7d64f49153424/pages/2576678921/SOQLParser
 * 
 * Closes the loop on our most useful SOQLParser / RKSecurity / RKShare features, and adds configurable Query Rules.
 * Queries should be issued thourgh a properly crafted SOQLContext instance, rather than via Database.query or inline SOQL 
 * queries (Apex bracket [] syntax).
 */
global class SOQLContext {

    global class AccessException extends Exception {
        global Integer numCRUD {get; public set;}
        global Integer numFLS {get; public set;}
    }

    // Wraps and consolidates all the SOQLParser-namespace exceptions that may have be thrown out:
    global class QueryException extends Exception {}

    private static void wrapAndRethrowParseErrors(Exception og) {
        if (og instanceof SOQLParser.ErrorException || 
            og instanceof SOQLParser.ParseException ||
            og instanceof SOQLParser.ReferenceException || 
            og instanceof SOQLParser.TypeException ||
            og instanceof SOQLParser.SerializerException ||
            og instanceof SOQLParser.EvaluationException) {

            QueryException qe = new QueryException(og.getMessage(), og);
            qe.setMessage(og.getMessage());
            //qe.initCause(og);
            throw qe;
        }
        //Assert.fail('Unrecognized error type: ' + og.getTypeName());
        throw og;
    }
 
    private static SOQLContext DefaultSystemMode;
    private static SOQLContext DefaultSafeMode;
    private static SOQLContext DefaultStrictMode;

    // =====================================================================================================================
    // Core SOQLContext API:
    // =====================================================================================================================

    // Static Convenience Methods For Issuing Queries:

    global static SObject[] systemQuery(String query) {
        return systemQuery(query, AllNullBinds);
    }

    global static SObject[] systemQuery(String query, Object bind1) {
        return systemQuery(query, new Object[]{ bind1 });
    }

    global static SObject[] systemQuery(String query, Object bind1, Object bind2) {
        return systemQuery(query, new Object[]{ bind1, bind2 });
    }

    global static SObject[] systemQuery(String query, Object bind1, Object bind2, Object bind3) {
        return systemQuery(query, new Object[]{ bind1, bind2, bind3 });
    }

    global static SObject[] systemQuery(String query, Object[] anonymousBindValues) {
        return standardSystemMode().query(query, null, anonymousBindValues);
    }

    global static SObject[] safeQuery(String query) {
        return safeQuery(query, AllNullBinds);
    }

    global static SObject[] safeQuery(String query, Object[] anonymousBindValues) {
        return standardSafeMode().query(query, null, anonymousBindValues);
    }

    global static SObject[] strictQuery(String query) {
        return strictQuery(query, AllNullBinds);
    }

    global static SObject[] strictQuery(String query, Object[] anonymousBindValues) {
        return standardStrictMode().query(query, null, anonymousBindValues);
    }

    @TestVisible
    private static Object[] AllNullBinds = new Object[]{ 
        null, null, null, null, null, null, null, null, null, null,
        null, null, null, null, null, null, null, null, null, null
    };

    // Static Constructors:

    // This instance is NOT cached and modifications to it ARE allowed (!sealed):
    global static SOQLContext newSystemMode() {
        return new SOQLContext('SystemMode', 'System-Mode')
            .systemSharing()
            .systemCrudFLS();
    }

    // This instance is NOT cached and modifications to it ARE allowed (!sealed):
    global static SOQLContext newSafeMode() {
        return new SOQLContext('SafeMode', 'Safe-Mode')
            .strictSharing()
            .throwCrudFilterFLS();
    }

    // This instance is NOT cached and modifications to it ARE allowed (!sealed):
    global static SOQLContext newStrictMode() {
        return new SOQLContext('StrictMode', 'Strict-Mode')
            .strictSharing()
            .strictCrudFLS();
    }

    // This instance is cached and modifications to it are NOT allowed (sealed):
    global static SOQLContext standardSystemMode() {
        if (DefaultSystemMode == null) {
            DefaultSystemMode = newSystemMode();
            DefaultSystemMode.sealed = true;
        }
        return DefaultSystemMode;
    }

    // This instance is cached and modifications to it are NOT allowed (sealed):
    global static SOQLContext standardSafeMode() {
        if (DefaultSafeMode == null) {
            DefaultSafeMode = newSafeMode();
            DefaultSafeMode.sealed = true;
        }
        return DefaultSafeMode;
    }

    // This instance is cached and modifications to it are NOT allowed (sealed):
    global static SOQLContext standardStrictMode() {
        if (DefaultStrictMode == null) {
            DefaultStrictMode = newStrictMode();
            DefaultStrictMode.sealed = true;
        }
        return DefaultStrictMode;
    }

    @TestVisible
    String name;
    @TestVisible
    String label;

    // Dictates whether further modifications to this SOQLContext specification are allowed:
    Boolean sealed = false;

    Integer securityMode = RKSecurity.FILTER_FLS_THROW_CRUD;
    Boolean securityModeTransactional = false;
    Boolean enforceCrudFLS = true;

    String bindTypesMode = 'loose'; // "loose", "strict"

    Set<Schema.sObjectType> recordAccessBypassTypes = new Set<Schema.sObjectType>{ 
        Schema.sObjectType.RecordType.getSObjectType(), // RecordType sObjectType metadata is a bit weird
        Schema.ContentVersion.sObjectType, Schema.ContentDocument.sObjectType, Schema.ContentDocumentLink.sObjectType,
        Schema.Attachment.sObjectType 
    };
    RKShare.AccessResolver customAccess;
    RKShare.SecurityModel sharingModel;

    Object[] anonVals = new Object[]{};
    Map<String, Object> namedVals = new Map<String, Object>();

    Boolean queryForUpdate = false;

    @testVisible
    //RestrictedSearch[] searchRules = new RestrictedSearch[]{};
    QueryRule rootRule;
    
    // New SOQLContext defaults to the following behaviors:
    // * Strict CRUD enforcement (throw error).
    // * Filtered FLS enforcement (e.g. silent removal of unreadable fields from SELECT clauses).
    // * SOQL queries execute in a "with sharing" context, which enforces platform sharing rules.
    // These behaviors can be changed / customized by using the builder methods defined below. 
    global SOQLContext(String name, String label) {
        setName(name, label);
        //this.name = name;
        //this.label = label;
        this.sharingModel = new RKShare.WithPlatformSharing();
    }

    global SOQLContext(String name) {
        this(name, name);
    }

    global SOQLContext() {
        this('AdHoc');
    }

    global SOQLContext forUpdate(Boolean queryForUpdate) {
        this.queryForUpdate = queryForUpdate == true;
        return this;
    }

    global SOQLContext looseBindTypes() {
        this.bindTypesMode = 'loose';
        return this;
    }

    global SOQLContext strictBindTypes() {
        this.bindTypesMode = 'strict';
        return this;
    }

    global SOQLContext bind(Object bindVal) {
        anonVals.add(bindVal);
        return this;
    }

    global SOQLContext bind(String bindName, Object bindVal) {
        namedVals.put(bindName, bindVal);
        return this;
    }

    global SOQLContext bindAll(Object[] bindVals) {
        anonVals.addAll(bindVals);
        return this;
    }

    global SOQLContext bindAll(Map<String, Object> namedBinds) {
        namedVals.putAll(namedBinds);
        return this;
    }

    global SOQLContext clearBindings() {
        this.anonVals = new Object[]{};
        this.namedVals = new Map<String, Object>();
        return this;
    }

    global SOQLContext fork(String name, String label) {
        SOQLContext forked = new SOQLContext(name, label);
        // forked copies are unsealed:
        forked.sealed = false;
        forked.securityMode = securityMode;
        forked.securityModeTransactional = securityModeTransactional;
        forked.enforceCrudFLS = enforceCrudFLS;
        forked.recordAccessBypassTypes = recordAccessBypassTypes.clone();
        forked.customAccess = customAccess;
        forked.sharingModel = sharingModel;
        forked.queryForUpdate = queryForUpdate;
        //forked.searchRules = searchRules.clone();
        forked.rootRule = rootRule != null ? rootRule.clone() : null;

        return forked;
    }

    public String name() {
        return name;
    }

    public void setName(String name) {
        setName(name, name);
    }

    public void setName(String name,  String label) {
        Assert.isTrue(String.isNotBlank(name), 'SOQLContext name cannot be blank');
        this.name = name;
        this.label = String.isBlank(label) ? name : label;
    }

    public Boolean isSealed() {
        return sealed == true;
    }

    public void assertNotSealed() {
        Assert.isFalse(sealed, 'SOQLContext "' + name + '" is sealed and cannot accept modification');
    }

    // "System Mode" CRUD/FLS. Does not assert CRUD nor FLS.
    global SOQLContext systemCrudFLS() {
        assertNotSealed();
        this.securityMode = RKSecurity.BYPASS_FLS_CRUD;
        this.enforceCrudFLS = false;
        return this;
    }

    // "Safe Mode" CRUD/FLS where any violation of either throws an error (i.e. non-silent, as opposed to filtering).
    global SOQLContext strictCrudFls() {
        assertNotSealed();
        this.securityMode = RKSecurity.ALL_OR_NONE;
        this.enforceCrudFLS = true;
        return this;
    }

    // Filters out CRUD and FLS violations without failing the query (filtered query proceeds):
    global SOQLContext filterCrudFls() {
        assertNotSealed();
        this.securityMode = RKSecurity.FILTER_FLS_CRUD;
        this.enforceCrudFLS = true;
        return this;
    }

    // Throws on CRUD violations (query fails), but silently filters out FLS violations (filtered query proceeds):
    global SOQLContext throwCrudFilterFls() {
        assertNotSealed();
        this.securityMode = RKSecurity.FILTER_FLS_THROW_CRUD;
        this.enforceCrudFLS = true;
        return this;
    }

    // Ignores all CRUD violations and FLS violations (no filtering, and query proceeds):
    global SOQLContext bypassCrudFls() {
        return systemCrudFLS();
    }

    // Throws on any CRUD or FLS violation (query fails):
    global SOQLContext strictSharing() {
        assertNotSealed();
        this.sharingModel = new RKShare.WithPlatformSharing();
        return this;
    }

    // "System Mode" sharing applies "without sharing" on query execution:
    global SOQLContext systemSharing() {
        assertNotSealed();
        // !! READ THE COMMENT ABOVE
        // The purpose of this method is to engage WithOUT Sharing - DO NOT change this to With Sharing:
        this.sharingModel = new RKShare.WithoutPlatformSharing(null);
        return this;
    }

    // "Custom Mode" sharing applies custom RKShare.AccessResover logic in a "without sharing" execution context:
    public SOQLContext customSharing(RKShare.AccessResolver customAccess) {
        assertNotSealed();
        this.customAccess = customAccess;
        this.sharingModel = new RKShare.WithoutPlatformSharing(customAccess);
        return this;
    }

    global SOQLContext setRule(QueryRule rule) {
        assertNotSealed();
        Assert.isNull(rootRule, 'Root-Rule had already been set, and cannot be redefined to ' + rule.getFailPath());
        Assert.isTrue(rule.isRoot == true || rule.isRoot == null && rule.parent == null, 
            'Context cannot accept rule ' + rule.getFailPath() + ' because it is not a root-level rule');
        rule.isRoot = true;
        rule.hostContext = this;
        this.rootRule = rule;
        return this;
    }

    global QueryRuleSet defineRuleSet(String name) {
        QueryRuleSet newRuleSet = new QueryRuleSet(name);
        setRule(newRuleSet);
        return newRuleSet;
    }

    //global SOQLContext addRule(RestrictedSearch rule) {
    //    assertNotSealed();
    //    searchRules.add(rule);
    //    return this;
    //}

    // "Custom Mode" sharing applies custom RKShare.AccessResover logic in a "without sharing" execution context.
    // "designatedUser" should hold Id and Name fields:
    global SOQLContext delegatedSharing(User designatedUser) {
        assertNotSealed();
        customSharing(new RKShare.DesignatedUserAccessResolver(recordAccessBypassTypes, designatedUser));
        return this;
    }

    global SObject[] query(String soql) {
        return query(soql, null, new Object[]{});
    }

    global SObject[] query(String soql, Map<String, Object> namedBinds) {
        return query(soql, namedBinds, null);
    }

    global SObject[] query(String soql, Object[] anonymousBinds) {
        return query(soql, null, anonymousBinds);
    }

    global SObject[] query(String queryString, Map<String, Object> namedBinds, Object[] anonymousBinds) {
        if (namedBinds != null) {
            this.namedVals.putAll(namedBinds);
        }
        if (anonymousBinds != null) {
            this.anonVals.addAll(anonymousBinds);
        }

        // Works like startSystemMode(), but only acts like System mode with regard to record sharing, not CRUD/FLS:
        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            RKSecurity.setSecurityMode(securityMode);
            if (securityModeTransactional) {
                RKSecurity.transactionalThrow();
            }
            
            // Uses a LocalReBindPool, e.g. Id[] ids0, ids1, ids2:
            SOQLParser.LocalRebindPool rebindPool = RKShare.mintRebindPool();
            SOQLParser.SOQL soql = 
                new SOQLParser.SOQL(queryString)
                    .forUpdate(this.queryForUpdate)
                    .bindTypesMode(bindTypesMode)
                    .rebindPool(rebindPool)
                    .vals(this.namedVals) //namedBinds)
                    .vals(this.anonVals) //anonymousBinds)
                    .resolve(enforceCrudFLS);
            
            assertRules(soql)
                .bind();
            return sharingModel.query(soql.ser(false), rebindPool);
        } catch (Exception e) {
            wrapAndRethrowParseErrors(e);
        } finally {
            RKSecurity.restore(sp);
            clearBindings();
        }
        return null; // unreachable
    }

    global Database.QueryLocator getQueryLocator(String queryString) {
        Map<String, Object> nullNamedBinds;
        Object[] nullAnonBinds;
        SOQLParser.LocalRebindPool nullPool;
        return Database.getQueryLocator(getQuery(queryString, nullNamedBinds, nullAnonBinds, nullPool));
    }

    // Returns the equivalent vanilla-SOQL query (can be run via Database.query or used to construct a QueryLocator)
    // after asserting the security levels and rules specified by this SOQLContext - which may either throw error, or
    // modify the resulting query:
    global String getQuery(String queryString, Map<String, Object> namedBinds, Object[] anonymousBinds, 
            SOQLParser.LocalRebindPool rebindPool) {
        
        try {
            return getSOQL(queryString, namedBinds, anonymousBinds, rebindPool).ser();
        } catch (SOQLParser.TypeException e) {
            wrapAndRethrowParseErrors(e);
        } catch (SOQLParser.SerializerException e) {
            wrapAndRethrowParseErrors(e);
        } catch (SOQLParser.ErrorException e) {
            wrapAndRethrowParseErrors(e);
        }
        return null; // unreachable
    }

    global String getQuery(String queryString, Object[] anonymousBinds) {
        Map<String, Object> emptyNamedBinds = new Map<String, Object>();
        SOQLParser.LocalRebindPool nullRebinds = null;
        return getQuery(queryString, emptyNamedBinds, anonymousBinds, nullRebinds);
    }

    global String getQuery(String queryString) {
        return getQuery(queryString, AllNullBinds);
    }

    global String getQuery(String queryString, Object val1) {
        return getQuery(queryString, new Object[]{ val1, null, null, null, null });
    }
    
    global String getQuery(String queryString, Object val1, Object val2) {
        return getQuery(queryString, new Object[]{ val1, val2, null, null, null });
    }
    
    global String getQuery(String queryString, Object val1, Object val2, Object val3) {
        return getQuery(queryString, new Object[]{ val1, val2, val3, null, null  });
    }

    global String getQuery(String queryString, Object val1, Object val2, Object val3, Object val4) {
        return getQuery(queryString, new Object[]{ val1, val2, val3, val4, null });
    }

    global String getQuery(String queryString, Object val1, Object val2, Object val3, Object val4, Object val5) {
        return getQuery(queryString, new Object[]{ val1, val2, val3, val4, val5 });
    }

    // =============================================================================================================

    global SOQLParser.SOQL getSOQL(String queryString) {
        return getSOQL(queryString, AllNullBinds);
    }

    global SOQLParser.SOQL getSOQL(String queryString, Object val1) {
        return getSOQL(queryString, new Object[]{ val1, null, null, null, null });
    }
    
    global SOQLParser.SOQL getSOQL(String queryString, Object val1, Object val2) {
        return getSOQL(queryString, new Object[]{ val1, val2, null, null, null });
    }
    
    global SOQLParser.SOQL getSOQL(String queryString, Object val1, Object val2, Object val3) {
        return getSOQL(queryString, new Object[]{ val1, val2, val3, null, null });
    }

    global SOQLParser.SOQL getSOQL(String queryString, Object val1, Object val2, Object val3, Object val4) {
        return getSOQL(queryString, new Object[]{ val1, val2, val3, val4, null });
    }

    global SOQLParser.SOQL getSOQL(String queryString, Object val1, Object val2, Object val3, Object val4, Object val5) {
        return getSOQL(queryString, new Object[]{ val1, val2, val3, val4, val5 });
    }

    global SOQLParser.SOQL getSOQL(String queryString, Object[] anonymousBinds) {
        Map<String, Object> emptyNamedBinds = new Map<String, Object>();
        SOQLParser.LocalRebindPool nullRebinds = null;
        return getSOQL(queryString, emptyNamedBinds, anonymousBinds, nullRebinds);
    }

    // Returns the equivalent vanilla-SOQL query (can be run via Database.query or used to construct a QueryLocator)
    // after asserting the security levels and rules specified by this SOQLContext - which may either throw error, or
    // modify the resulting query:
    global SOQLParser.SOQL getSOQL(String queryString, Map<String, Object> namedBinds, Object[] anonymousBinds, 
            SOQLParser.LocalRebindPool rebindPool) {
        
        if (namedBinds != null) {
            this.namedVals.putAll(namedBinds);
        }
        if (anonymousBinds != null) {
            this.anonVals.addAll(anonymousBinds);
        }

        // Works like startSystemMode(), but only acts like System mode with regard to record sharing, not CRUD/FLS:
        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            RKSecurity.setSecurityMode(securityMode);
            if (securityModeTransactional) {
                RKSecurity.transactionalThrow();
            }
            
            // Uses a LocalReBindPool, e.g. Id[] ids0, ids1, ids2:
            //SOQLParser.LocalRebindPool rebindPool = RKShare.mintRebindPool();
            SOQLParser.SOQL soql = 
                new SOQLParser.SOQL(queryString)
                    .forUpdate(this.queryForUpdate)
                    .bindTypesMode(bindTypesMode);
            
            if (rebindPool != null) {
                soql.rebindPool(rebindPool);
            }
            soql.vals(this.namedVals) //namedBinds)
                .vals(this.anonVals) //anonymousBinds)
                //.bind()
                .resolve(enforceCrudFLS);
            
            assertRules(soql)
                .bind();
            //return sharingModel.query(soql.ser(false), rebindPool);

            // We call serialization, even as we discard its value, just to tigger any potential Serialization 
            // exceptions before returning. This way we know the returned SOQL is completely valid against the 
            // full specifications of this SOQLContext:
            //soql.ser(false);
            return soql;
        } catch (Exception e) {
            wrapAndRethrowParseErrors(e);
        } finally {
            RKSecurity.restore(sp);
            clearBindings();
        }
        return null; // unreachable
    }

    // =============================================================================================================

    // Throws RuleViolationException:
    global SOQLParser.SOQL validate(String queryString) {
        // Works like startSystemMode(), but only acts like System mode with regard to record sharing, not CRUD/FLS:
        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            RKSecurity.setSecurityMode(securityMode);
            if (securityModeTransactional) {
                RKSecurity.transactionalThrow();
            }
            
            SOQLParser.SOQL soql = new SOQLParser.SOQL(queryString)
                .forUpdate(this.queryForUpdate)
                .bindTypesMode(bindTypesMode)
                .resolve(enforceCrudFLS);

            return assertRules(soql);
        } catch (Exception e) {
            wrapAndRethrowParseErrors(e);
        } finally {
            RKSecurity.restore(sp);
            clearBindings();
        }
        return null; // unreachable
    }

    // Throws RuleViolationException, RuleConfigurationException:
    private SOQLParser.SOQL assertRules(SOQLParser.SOQL soql) {
        if (rootRule != null) {
            rootRule.init();
            try {
            rootRule.assert(soql);
            } catch (RuleViolationException err) {
                String ogMessage =  err.getMessage();
                // If the root rule has configured a custom error message, then use that. We will still log the original 
                // rule violation message:
                if (String.isNotBlank(rootRule.customMessage)) {
                    err.originalMessage = ogMessage;
                    err.setMessage(rootRule.customMessage);
                }
                System.debug(LoggingLevel.ERROR, ogMessage);
                throw err;
            }
        }
        return soql;
    }

    // =====================================================================================================================
    // NEW Evaluator Module Hooks:
    // =====================================================================================================================

    global SOQLEvaluator getEvaluatorWithoutBinds(Schema.sObjectType queryType, String whereClauseString) {
        whereClauseString = whereClauseString.trim();
        String fullQuery;
        String conditionPrefix;
        if (whereClauseString.startsWithIgnoreCase('SELECT') || whereClauseString.startsWithIgnoreCase('FROM')) {
            fullQuery = whereClauseString;
        } else {
            conditionPrefix = 'FROM ' + queryType + ' ' 
                + (whereClauseString.startsWithIgnoreCase('WHERE') ? '' : 'WHERE ');
            fullQuery = conditionPrefix + whereClauseString;
        }

        // !! TODO: The SOQLLexer.CursorAdjustForPrefix() and CursorAdjustReset() calls are a HACK for now to adjust for the 
        // generated "FROM {queryType} WHERE " clause prefix, so that they don't confuse the reported Line and Column #'s of
        // reported parse errors:
        if (conditionPrefix != null) {
            SOQLLexer.CursorAdjustForPrefix(conditionPrefix);
        }
        try {
            return getEvaluatorWithoutBinds(fullQuery);
        } finally {
            SOQLLexer.CursorAdjustReset();
        }
    }

    global SOQLEvaluator getEvaluatorWithoutBinds(String queryString) {
        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            // In-mem evals should be SYSTEM mode by default:
            RKSecurity.setSecurityMode(RKSecurity.BYPASS_FLS_CRUD);
            final Boolean evalWithoutCrudFLS = false;
            return new SOQLEvaluator(this, 
                new SOQLParser.SOQL(queryString)
                    .resolve(evalWithoutCrudFLS) //this.enforceCrudFLS)
                    .resolveWhereClauseReferences())
                .withoutBinds();
        } catch (Exception e) {
            wrapAndRethrowParseErrors(e);
        } finally {
            RKSecurity.restore(sp);
            clearBindings();
        }
        return null; // unreachable
    }

    global SOQLEvaluator getEvaluatorWithBinds(String queryString) {
        // TODO:
        Assert.fail('SOQLEvaluator WITH binds not yet supported.');

        RKSecurity.SecuritySavepoint sp = new RKSecurity.SecuritySavepoint();
        try {
            // In-mem evals should be SYSTEM mode by default:
            RKSecurity.setSecurityMode(RKSecurity.BYPASS_FLS_CRUD);
            final Boolean evalWithoutCrudFLS = false;
            return new SOQLEvaluator(this, 
                new SOQLParser.SOQL(queryString)
                    .bindTypesMode(this.bindTypesMode)
                    // TODO: bind points should be extracted from SOQLParser and managed on the SOQLEvaluator...
                    .vals(this.namedVals) //namedBinds)
                    .vals(this.anonVals) //anonymousBinds)
                    .resolve(evalWithoutCrudFLS) //this.enforceCrudFLS)
                    .bind())
                .withBinds();
        } catch (Exception e) {
            wrapAndRethrowParseErrors(e);
        } finally {
            RKSecurity.restore(sp);
            clearBindings();
        }
        return null; // unreachable
    }

    // =====================================================================================================================
    // ASTVisitor Implementations:
    // =====================================================================================================================

    global class SOQLVisitorConfigurationException extends Exception {
        global SOQLVisitor visitor;
    }
    
    global class SOQLVisitorViolationException extends Exception {
        global SOQLVisitor visitor;
    }
    
    global virtual class SOQLVisitor extends SOQLParser.ASTVisitor {
        global Schema.SObjectType targetType {get; private set;}
        global String name {get; private set;}
    
        global SOQLVisitor(Schema.SObjectType targetType, String name) {
            this.targetType = targetType;
            this.name = name;
        }
    
        global virtual override void reset() {
            super.reset();
        }
    
        // Throws SOQLVisitorConfigurationException:
        global void throwConfig(String msg) {
            SOQLVisitorConfigurationException e = new SOQLVisitorConfigurationException(msg);
            e.visitor = this;
            e.setMessage(msg);
            throw e;
        }
    
        // Throws SOQLVisitorViolationException:
        global void throwViolation(String msg) {
            SOQLVisitorViolationException e = new SOQLVisitorViolationException(msg);
            e.visitor = this;
            e.setMessage(msg);
            throw e;
        }
    
        global virtual void start(SOQLParser.SOQL soql) {}
    
        global virtual void finish(SOQLParser.SOQL soql) {}
    }

    public abstract class MatchElmt {
        String path;
    }

    public class ExactMatchElmt extends MatchElmt {
        Boolean isRequired = true;
    }

    public class FreestyleElmt extends MatchElmt {
        Boolean allowNested;
        Boolean allowAnyOp;
    }
    
    global class EnforceSearchTermsVisitor extends SOQLVisitor {
        Map<String, ExactMatchElmt> matchElmtsByPathLC = new Map<String, ExactMatchElmt>();
        Map<String, FreestyleElmt> freeElmtsByPathLC = new Map<String, FreestyleElmt>();
        Integer minimumMatches;
        Integer matchesCounter;
        // As we encounter match and freestyle elements in a parsed WHERE clause, they are logged here:
        Map<String, SOQLParser.ASTSimpleCond> parsedElmtsByPathLC = new Map<String, SOQLParser.ASTSimpleCond>();
    
        global EnforceSearchTermsVisitor(Schema.SObjectType targetType, String name) {
            super(targetType, name);
        }
    
        global virtual override void reset() {
            super.reset();
            matchesCounter = 0;
        }
    
        // This method can also be used to fire start-up validations (e.g. invalid configurations):
        global override void start(SOQLParser.SOQL soql) {
            this.matchesCounter = 0;
            this.parsedElmtsByPathLC = new Map<String, SOQLParser.ASTSimpleCond>();
            if (soql.resTable != targetType) {
                throwViolation('Illegal "FROM ' + soql.fromEntity.lexeme + '" clause; only "FROM ' + 
                    targetType + '" is allowed');
            }
            if (soql.whereCond == null) {
                throwViolation('WHERE clause is required');
            }
            /* TODO: Review...
            if (soql.sorts != null && soql.sorts.size() > 0) {
                throwViolation('ORDER BY clause is not allowed');
            }
            */
            if (soql.nested != null && soql.nested.size() > 0) {
                throwViolation('SELECT of child relationships is not allowed');
            }
            if (matchElmtsByPathLC.keySet().size() == 0) {
                throwViolation('At least 1 match must be defined');
            }
            if (minimumMatches != null && minimumMatches < 0) {
                throwViolation('Minimum # of matches must be set to a non-negative integer; got ' + minimumMatches);
            }
        }
    
        global override void finish(SOQLParser.SOQL soql) {
            // Verify we got all match elements that were flagged as required:
            for (ExactMatchElmt matchElmt : matchElmtsByPathLC.values()) {
                if (matchElmt.isRequired) {
                    if (!parsedElmtsByPathLC.containsKey(matchElmt.path.toLowerCase())) {                    
                        throwViolation('Required match term "' + matchElmt.path + '" is not present');
                    }
                }
            }
            // Verify we got the minimum number of matches:
            Integer effectiveMin = getEffectiveMinMatches();
            if (matchesCounter < effectiveMin) {
                throwViolation('Expected at least ' + effectiveMin + ' match terms; got ' + matchesCounter);
            }
        }
    
        //global override void onStart(ASTCond root) {}
        
        global override void onCond(ASTCond cond) {
            if (cond.isOr() || cond.isNot()) {
                ASTCond parentAnd;
                for (ASTCond parent : parents()) {
                    if (parent.isAnd()) {
                        parentAnd = parent;
                        break;
                    }
                }
                if (parentAnd == null) {
                    throwViolation((cond.isOr() ? 'OR' : 'NOT') + ' condition must be nested under a parent AND');
                }
            } else if (cond.isSimple()) {
                // These structure flags tell us where this simple condition resides within the query's 
                // AST tree structure. Exact-match elements are only allowed as the top-level conditon or
                // directly under a top-level AND condition. Freestyle elements are allowed at deeper 
                // nestings, though note other rules (above) prevent the existence of OR and NOT at the
                // top level:
                Boolean isTop = false;
                Boolean isTopAND = false;
                Boolean allParentsAND = true;
                ASTCond[] filteredParents = parents().clone();
                // Remove any redundant groupings at the top levels:
                Integer top = filteredParents.size() - 1;
                while (top >= 0) {
                    if (filteredParents[top].isGroup()) {
                        filteredParents.remove(top--);
                        continue;
                    } else {
                        break;
                    }
                }
                if (filteredParents.size() == 0) {
                    isTop = true;
                } else {
                    for (ASTCond parent : filteredParents) { //parents()) {
                    //// Extra groupings don't change our structure analysis:
                    //if (parent.isGroup()) {
                    //    continue;
                    //} else {
                    isTop = false;
                    // If it's under an OR or NOT then it can only qualify for "freestyle" elements. 
                    // Set both structure flags false, and we're done:
                    if (parent.isOr() || parent.isNot()) {
                        isTopAND = false;
                        allParentsAND = false;
                        break;
                    } else if (parent.isAnd()) {
                        // If it's under an AND but we were already under another AND then it's more
                        // deeply nested than top level. Set both structure flags false, and we're done:
                        if (isTopAND) {
                            isTopAND = false;
                            break;
                        // If it's under an AND and this is the first one, then it (currently) qualifies
                        // as a top-level AND. Set the isTopAND structure flag to true and continue:
                        } else {
                            isTopAND = true;
                            continue;
                        }
                    }
                    //}
                    }
                }
    
                SOQLParser.ASTSimpleCond simpleCond = (SOQLParser.ASTSimpleCond) cond;
                String path = simpleCond.ref.getBestPath();
                ExactMatchElmt matchElmt = matchElmtsByPathLC.get(path.toLowerCase());
                FreestyleElmt freeElmt;
                if (matchElmt != null) {
                    //if (!isTop && !isTopAND) {
                    if (!(isTop || allParentsAND)) {
                        throwViolation('Match term "' + path + 
                            //'" cannot be nested deeper than a top-level AND condition');
                            '" may not bind to OR or NOT');
                    } else if (simpleCond.op.lexeme != '=') {
                        throwViolation('Match term "' + path + '" is only allowed "="; got "' + 
                            simpleCond.op.lexeme + '"');
                    } else if (simpleCond.val.isList()) {
                        throwViolation('Match term "' + path + 
                            '" is only allowed simple match values; got list value');
                    } else if (simpleCond.val.isUnboundNamedParam()) {
                        throwViolation('Match term "' + path + 
                            '" is not allowed unresolved named bind ":' + 
                            simpleCond.val.scalar.param.lexeme + '"');
                    } else {
                        matchesCounter++;
                    }
                } else {
                    freeElmt = freeElmtsByPathLC.get(path.toLowerCase());
                    if (freeElmt != null) {
                        if (freeElmt.allowNested != true && !isTop && !isTopAND) {
                            throwViolation('Freestyle term "' + path + 
                                '" cannot be nested deeper than a top-level AND condition');
                        } else if (freeElmt.allowAnyOp != true && simpleCond.op.lexeme != '=') {
                            throwViolation('Freestyle term "' + path + 
                                '" is only allowed the "=" operator; got "' + simpleCond.op.lexeme + '"');
                        }
                    // Else we have an undefined reference path, which is a violation!
                    } else {
                        throwViolation('Field reference "' + path + 
                            '" has not been defined as either match term or freestyle term');
                    }
                }
    
                MatchElmt parsedElmt = (MatchElmt) matchElmt ?? (MatchElmt) freeElmt;
                if (parsedElmt != null) {
                    SOQLParser.ASTSimpleCond duplicateCond = 
                        parsedElmtsByPathLC.put(parsedElmt.path.toLowerCase(), simpleCond);
                    // Prevent duplicate instances of the same match element in a WHERE clause:
                    if (duplicateCond != null && parsedElmt instanceof ExactMatchElmt) {
                        throwViolation('Match term "' + parsedElmt.path + 
                            '" cannot be used more than once');
                    }
                }
            }
        }
    
        //global override void onLeaveCond(ASTCond cond) {}
        //global override void onValue(ASTValue val) {}
        //global override void onReference(ASTReference ref) {}
        //global override void onFinish(ASTCond root) {}
    
        global Integer getEffectiveMinMatches() {
            if (minimumMatches != null) {
                return minimumMatches;
            }
            // TODO: relaxing the minimum matches logic for now - it may be bypassed by setting to 0 
            // or null (defaults to 0):
            return 0;
            /*
            Integer effectiveMin = 0;
            for (ExactMatchElmt matchElmt : matchElmtsByPathLC.values()) {
                if (matchElmt.isRequired) {
                    effectiveMin++;
                }
            }
            if (effectiveMin == 0) {
                effectiveMin = matchElmtsByPathLC.keySet().size();
            }
            return effectiveMin;
            */
        }
    
        global EnforceSearchTermsVisitor setMinimumMatches(Integer minMatches) {
            this.minimumMatches = minMatches;
            return this;
        }
    
        // Specifies an exact-match field. 
        // 1. A field condition to this path may only exist at either the conditon's top level, or 
        //    nested under AND's and Groups ONLY (no OR's or NOT's). Its appearance at other structural 
        //    position will fail this rule.
        // 2. A field condition to this path must only use a strict equals '=' operator. Use of any
        //    other operator will fail this rule.
        // 3. Any duplicate field condition on this same path will fail this rule. 
        // 4. If marked as required, a field condition to this path MUST exist in the WHERE condition,
        //    adherent to the above rules, or this rule will fail.
        // 5. A field condition to this path, and adherent to above rules, will increment the 
        //    "matchesCount" counter by 1. If, after processing the entire WHERE condition, 
        //    (matchesCounter < minimumMatches), this rule will fail.
        global EnforceSearchTermsVisitor addExactMatchElement(String path, Boolean isRequired) {
            ExactMatchElmt matchElmt = new ExactMatchElmt();
            matchElmt.path = path;
            matchElmt.isRequired = isRequired == true;
            String pathLC = path.toLowerCase();
            ExactMatchElmt oldElmt = matchElmtsByPathLC.put(pathLC, matchElmt);
            if (oldElmt != null) {
                throwConfig('Match term "' + path + '" was previously defined');
            }
            if (freeElmtsByPathLC.containsKey(pathLC)) {
                throwConfig('Match term "' + matchElmt.path + 
                    '" clashes with existing freestyle term of same path');
            }
            return this;
        }
    
        // Specifies an optional condition field. This path must NOT match that of any "exact match" 
        // element. A field condition to this path may exist at any level, with any operator. However, the 
        // basic ruleset for RestrictedByExactMatches still applies:
        // 1. An OR is only allowed if nested under an AND
        // 2. A NOT is only allowed if nested under an AND
        // 3. Field conditons may only use scalar literal values. List values and binding / parameter 
        //    values are not allowed, and will fail this rule. 
        // 4. Any field condition not to a path for either "exact match" or "freestyle" elements will fail 
        //    this rule.
        global EnforceSearchTermsVisitor addFreestyleElement(String path, Boolean allowNested, Boolean allowAnyOp) {
            FreestyleElmt freeElmt = new FreestyleElmt();
            freeElmt.path = path;
            freeElmt.allowNested = allowNested == true;
            freeElmt.allowAnyOp = allowAnyOp == true;
            String pathLC = path.toLowerCase();
            FreestyleElmt oldElmt = freeElmtsByPathLC.put(pathLC, freeElmt);
            if (oldElmt != null) {
                throwConfig('Freestyle term "' + path + '" was previously defined');
            }
            if (matchElmtsByPathLC.containsKey(pathLC)) {
                throwConfig('Freestyle term "' + freeElmt.path + 
                    '" clashes with existing match term of same path');
            }
            return this;
        }
    }

    // =====================================================================================================================
    // QueryRule and QueryRuleSet:
    // =====================================================================================================================
    
    global class RuleConfigurationException extends Exception {
        global QueryRule rule;
    }

    global class RuleViolationException extends Exception {
        global QueryRule rule;
        global String originalMessage;
    }
    
    global class MetadataRuleUndefinedException extends Exception {
        global Schema.SObjectType targetType;
        global String targetName;
    }
    
    global static void ruleViolation(QueryRule rule, String message) {
        String fullMessage =  headeredMessage(rule, message);
        RuleViolationException err = new RuleViolationException(fullMessage);
        err.setMessage(fullMessage);
        err.rule = rule;
        throw err;
    }

    global static void configError(String fullMessage) {
        RuleConfigurationException err = new RuleConfigurationException(fullMessage);
        err.setMessage(fullMessage);
        //err.rule = rule;
        throw err;
    }
    
    global static void configError(QueryRule rule, String message) {
        String fullMessage = headeredMessage(rule, message);
        RuleConfigurationException err = new RuleConfigurationException(fullMessage);
        err.setMessage(fullMessage);
        err.rule = rule;
        throw err;
    }
    
    global static void metadataUndefined(QueryRule rule, String message) {
        String fullMessage = headeredMessage(rule, message);
        MetadataRuleUndefinedException err = new MetadataRuleUndefinedException(fullMessage);
        err.setMessage(fullMessage);
        //err.rule = rule;
        throw err;
    }
    
    global static String headeredMessage(QueryRule rule, String message) {
        String[] pathParts = rule.getFailPath();
        String pathDescrip = '[' + (pathParts.size() == 0 ? 'Anonymous Rule' : String.join(pathParts, '][')) + ']';
        return pathDescrip + ': ' + message;
    }

    global virtual class QueryRule {
        public Boolean isRoot = null;
        public String header;
        public QueryRuleSet parent;
        public Boolean initialized = false;
        // Custom message to display for Rule Violations - this should only be set on the root rule set:
        public String customMessage;
    
        // The following are utilized only by root rules:
        public MetadataRule[] registeredMetadata = new MetadataRule[]{};
        public Schema.SObjectType registeredTargetType;
        SOQLContext hostContext;
    
        public QueryRule() {
            this(null);
        }
    
        public QueryRule(String header) {
            this.header = header;
        }
    
        public void registerMetadata(MetadataRule meta) {
            if (this.isRoot == false) {
                configError(this, 'Only a Root-Rule can register metadata');
            }
            // Once a rule acts as a registry, it must be flagged as root and can no longer accept a parent:
            this.isRoot = true;
            registeredMetadata.add(meta);
        }
    
        public void registerTargetType(Schema.SObjectType targetType) {
            if (targetType == null) {
                configError(this, 'Cannot register target type null');
            } else if (this.isRoot == false) {
                configError(this, 'Only a Root-Rule can register target type');
            }
            // Once a rule acts as a registry, it must be flagged as root and can no longer accept a parent:
            this.isRoot = true;
            if (registeredTargetType != null && registeredTargetType != targetType) {
                configError(this, 'Target type ' + targetType + 
                    ' clashes with previously registered type ' + registeredTargetType);
            }
            this.registeredTargetType = targetType;
        }

        global QueryRuleSet parent() {
            // Here we're assuming only a QueryRuleSet can be a parent, which *should* be a valid assumption...
            if (parent != null) {
                return parent;
            } else if (this instanceof QueryRuleSet) {
                return (QueryRuleSet) this;
            }
            configError(this, 'Parent() request is invalid. Non-container QueryRule has no parent.');
            return null; // unreachable
        }

        global SOQLContext context() {
            QueryRule root = getRoot();
            Assert.isNotNull(root.hostContext, getFailPath() + ' does not have a host context');
            return root.hostContext;
        }
    
        // Throws MetadataRuleUndefinedException
        global virtual Boolean init() {
            if (initialized != true) {
                initialized = true;
                if (parent == null) {
                    this.isRoot = true;
                }
    
                if (isRoot && registeredMetadata.size() > 0) {
                    Assert.fail('Metadata Rules not supported');
                    /*
                    if (registeredTargetType == null) {
                        // This should not typically be reachable, since the call to add & register the metadata should have 
                        // thrown a config error (for this same reason) at that time: 
                        configError(this, 'Cannot initialize rule metadata without defining a target type');
                    }
                    // Load and resolve all registeredMetadata, setting the results on each corresponding MetadataRule.meta:
                    final String targetObjectApi = '' + registeredTargetType;
                    String[] generalUserScopes = new String[]{ 'All Users' };
                    if (UserInfo.getUserType() == 'Guest') {
                        generalUserScopes.add('Guest Users');
                    }
                    String[] targetNames = new String[]{};
                    for (MetadataRule mrule: registeredMetadata) {
                        targetNames.add(mrule.targetName);
                    }
                    Restricted_Search__mdt[] candidateRows = [ 
                        SELECT MasterLabel, DeveloperName, Object_Type__r.QualifiedApiName, Query_Mode__c, 
                            User_Scope__c, Object_Type__c, Minimum_Matches__c
                        FROM Restricted_Search__mdt 
                        WHERE Object_Type__r.QualifiedApiName = :targetObjectApi
                            //AND Target__c IN :targetNames
                            AND DeveloperName IN :targetNames
                            AND User_Scope__c IN :generalUserScopes
                            // !! OR conditions are not currently supported on Metadata queries. WTF?! Who at SF was asleep at the 
                            // wheel when they built this crap. Scuttling "Specific User" facility for now...
                            //AND (User_Scope__c IN :generalUserScopes
                            //    OR (User_Scope__c = 'Specific User' AND Specific_User_Id__c = :UserInfo.getUserId()))
                    ];
    
                    Map<String, MetadataRule> metaRulesByDevName = new Map<String, MetadataRule>();
                    for (MetadataRule mrule : registeredMetadata) {
                        // If we find multiple qualifying metadata matches, rank them first by the MOST specific match criteria, 
                        // and then by the LEAST restrictive search rules:
                        Restricted_Search__mdt bestMatchRow;
                        double bestMatchRank = -1;
                        for (Restricted_Search__mdt candidate: candidateRows) {
                            //if (candidate.Target__c != mrule.targetName) {
                            if (candidate.DeveloperName != mrule.targetName) {
                                continue;
                            }
                            double rank = rankSpecificity(candidate);
                            if (rank > bestMatchRank) {
                                bestMatchRow = candidate;
                                bestMatchRank = rank;
                            }
                            // TODO: optionally, we can throw a configError (Ambiguous Definition) if we get 2 or more candidates 
                            // with the same rank...
                        }
    
                        if (bestMatchRow != null) {
                            metaRulesByDevName.put(bestMatchRow.DeveloperName, mrule);
                            mrule.metaRow = bestMatchRow;
                        } else {
                            metadataUndefined(this, 'Metadata rule not defined for [' + mrule.targetName + 
                                '] on ' + registeredTargetType);
                        }
                    }
    
                    // Query related child fields metadata:
                    for (Restricted_Search_Field__mdt fieldRow : [ 
                            SELECT Restricted_Search__r.DeveloperName, DeveloperName, Applies_to_Minimum_Matches__c, 
                                Required__c, Search_Field__r.QualifiedApiName 
                            FROM Restricted_Search_Field__mdt 
                            WHERE Restricted_Search__r.DeveloperName IN :metaRulesByDevName.keySet() ]) {
                        metaRulesByDevName.get(fieldRow.Restricted_Search__r.DeveloperName).metaFieldRows.add(fieldRow);
                    }
                    */
                }
                return true;
            }
            return false;
        }

        /*
        private double rankSpecificity(Restricted_Search__mdt candidate) {
            double specificity;
            // Primarily, give a higher rank to more specifically-targeted searches:
            switch on candidate.User_Scope__c {
                when 'Specific User' {
                    specificity = 2.0;
                }
                when 'Guest Users' {
                    specificity = 1.0;
                } 
                when else {
                    specificity = 0.0;
                }
            }
            // Secondarily, give a higher rank to less-restricted (broader) searches:
            if (candidate.Query_Mode__c == 'Without Sharing') {
                specificity += 0.1;
            }
            if (candidate.Minimum_Matches__c == null || candidate.Minimum_Matches__c == 0.0) {
                specificity += 0.1;
            } else {
                specificity += 1.0 / (10.0 + Math.abs(candidate.Minimum_Matches__c));
            }
            return specificity;
        }
        */
    
        global QueryRule getRoot() {
            QueryRule[] parents = getParents();
            if (parents.size() == 0) {
                return this;
            }
            return parents[parents.size() - 1];
        }
    
        global QueryRule[] getParents() {
            QueryRule[] parents = new QueryRule[]{};
            QueryRule next = this;
            while (next != null) {
                next = next.parent;
                if (next == null) {
                    break;
                }
                parents.add(next);
            }
            return parents;
        }
    
        global virtual String[] getFailPath() {
            String[] parts = new String[]{};
            if (parent != null) {
                parts.addAll(parent.getFailPath());
            }
            parts.addAll(getFailHeader());
            return parts;
        }
    
        global virtual String[] getFailHeader() {
            if (String.isNotBlank(header)) {
                return new String[]{ header };
            }
            return new String[]{};
        }
    
        // throw RuleViolationException
        global virtual void assert(SOQLParser.SOQL soql) {}
    }
    
    global class WhereClauseRequired extends QueryRule {
        public WhereClauseRequired() {
            super(null);
        }
    
        global override void assert(SOQLParser.SOQL soql) {
            if (soql.whereCond == null) {
                ruleViolation(this, 'WHERE clause is required');
            }
        }
    }
    
    global class FromClauseTarget extends QueryRule {
        public Schema.SObjectType targetType;
    
        public FromClauseTarget() {
            super(null);
        }
    
        global FromClauseTarget(Schema.SObjectType targetType) {
            this.targetType = targetType;
        }
    
        global override void assert(SOQLParser.SOQL soql) {
            if (soql.resTable != targetType) {
                ruleViolation(this, 'Illegal FROM clause to ' + soql.fromEntity.lexeme + 
                    '; only ' + targetType + ' is allowed');
            }
        }
    }
    
    global virtual class SOQLStructureRule extends QueryRule {
        public SOQLVisitor visitor;
    
        public SOQLStructureRule(SOQLVisitor visitor) {
            super(visitor != null ? visitor.name : null);
            this.visitor = visitor;
        }
    
        global virtual override Boolean init() {
            if (super.init()) {
                if (visitor == null) {
                    configError(this, 'SOQL Visitor was not specified');
                }
                return true;
            }
            return false;
        }
    
        // Throws RuleViolationException
        global virtual override void assert(SOQLParser.SOQL soql) {
            try {
                visitor.reset();
                visitor.start(soql);
                if (soql.whereCond != null) {
                    // Throws SOQLVisitorViolationException:
                    soql.whereCond.traverse(visitor);
                }
                visitor.finish(soql);
            } catch(SOQLVisitorViolationException err) {
                // Re-wrap and re-throw the underlying SOQLVisitor error:
                ruleViolation(this, err.getMessage());
            }
        }
    }

    global class RestrictedSearchTermsRule extends SOQLStructureRule {
        Schema.SObjectType targetType;

        public RestrictedSearchTermsRule(Schema.SObjectType targetType, String ruleName) {
            // Initialize an empty condition-visitor. The visitor will be filled-out from metadata rows in this.init():
            super(new EnforceSearchTermsVisitor(targetType, ruleName));
            this.targetType = targetType;
        }

        private EnforceSearchTermsVisitor getSearchTermsVisitor() {
            return (EnforceSearchTermsVisitor) visitor;
        }

        global RestrictedSearchTermsRule minimumMatches(Integer minMatches) {
            getSearchTermsVisitor().setMinimumMatches(minMatches);
            return this;
        }

        global RestrictedSearchTermsRule matchTerm(String fieldPath) {
            getSearchTermsVisitor().addExactMatchElement(fieldPath, false);
            return this;
        }

        global RestrictedSearchTermsRule requiredMatchTerm(String fieldPath) {
            getSearchTermsVisitor().addExactMatchElement(fieldPath, true);
            return this;
        }

        global RestrictedSearchTermsRule freestyleTerm(String fieldPath) {
            getSearchTermsVisitor().addFreestyleElement(fieldPath, false, false);
            return this;
        }

        global QueryRuleSet endSearchTerms() {
            return parent();
        }
    }
    
    global class MetadataRule extends SOQLStructureRule {
        Schema.SObjectType targetType;
        String targetName;
        //Restricted_Search__mdt metaRow;
        //Restricted_Search_Field__mdt[] metaFieldRows = new Restricted_Search_Field__mdt[]{};
    
        public MetadataRule(Schema.SObjectType targetType, String targetName) {
            // Initialize an empty condition-visitor. The visitor will be filled-out from metadata rows in this.init():
            super(new EnforceSearchTermsVisitor(targetType, targetName));
            //this.header = targetType.getDescribe().getName() + ': ' + targetName;
            this.targetType = targetType;
            this.targetName = targetName;
        }

        //global override String[] getFailHeader() {
        //    return new String[]{ '' + targetType, targetName };
        //}
        
        // Throws RuleConfigurationException:
        global override Boolean init() {
            if (super.init()) {
                Assert.fail('MetadataRule not supported');
                /*
                if (targetType == null) {
                    configError(this, 'Metadata Rule must define a target type');
                }
                // Remember, we've consolidated metadata loading into registerMetadata on root...
                if (metaRow == null) {
                    configError(this, 'Metadata Rule was not pre-loaded by root');
                }
                
                try {
                    EnforceSearchTermsVisitor termsVisitor = (EnforceSearchTermsVisitor) visitor;
                    Integer minMatches = 0;
                    if (metaRow.Minimum_Matches__c != null) {
                        termsVisitor.setMinimumMatches(minMatches = metaRow.Minimum_Matches__c.intValue());
                    }
                    if (minMatches < 0) {
                        configError(this, 'Minimum matches must be set to a non-negative integer');
                    }
                    for (Restricted_Search_Field__mdt fieldRow : metaFieldRows) {
                        // Add field-level rules via SOQLContext.addExactMatchElement() and/or .addFreestyleElement():
                        if (fieldRow.Applies_to_Minimum_Matches__c == true) {
                            termsVisitor.addExactMatchElement(
                                fieldRow.Search_Field__r.QualifiedApiName, fieldRow.Required__c == true);
                        } else {
                            // !! The "allowNested" and "allowAnyOp" arguments are hardcoded to false for now, but we may 
                            // choose to externalize these as metadata fields later on:
                            termsVisitor.addFreestyleElement(
                                fieldRow.Search_Field__r.QualifiedApiName, false, false);
                        }
                    }
                } catch (SOQLVisitorConfigurationException err) {
                    // Re-wrap and re-throw the underlying SOQLVisitor error:
                    configError(this, err.getMessage());
                }
                return true;
                */
            }
            return false;
        }
    }
    
    public virtual class MetadataFieldTerm {
        String path;
    }
    
    public class MetadataMatchTerm extends MetadataFieldTerm {
        Boolean isRequired = false;
    }
    
    class MetadataFreestyleTerm extends MetadataFieldTerm {
        Boolean allowNested;
        Boolean allowAnyOp;
    }
    
    public final static Integer MATCH_ALL = 0;
    public final static Integer MATCH_ANY = 1;

    global class QueryRuleSet extends QueryRule {
        public Integer matchMode = MATCH_ALL;
        public QueryRule[] subRules = new QueryRule[]{};
        public Schema.SObjectType targetType;
    
        global QueryRuleSet(String header) {
            super(header);
        }
    
        global QueryRuleSet() {
            super(null);
        }
    
        global virtual override String[] getFailHeader() {
            if (header == null && matchMode == MATCH_ANY) {
                Integer len = subRules.size();
                String[] headerParts = new String[]{};
                if (len < 2) {
                    headerParts.add('Match Any');
                } else {
                    headerParts.add('Match Any of ' + len);
                    headerParts.add('Last Violation');
                }
                return headerParts;
                //return new String[]{ 'Match Any' + (subRules.size() > 0 ? ' of ' + subRules.size() : ''), 'Last Violation' };
            }
            return super.getFailHeader();
        }
    
        global override Boolean init() {
            if (super.init()) {
                for (QueryRule subRule : subRules) {
                    subRule.init();
                }
                return true;
            }
            return false;
        }

        // Custom message to display for Rule Violations - this should only be set on the root rule set:
        global QueryRule setCustomMessage(String msg) {
            this.customMessage = msg;
            return this;
        }
    
        global QueryRuleSet matchAny() {
            this.matchMode = MATCH_ANY;
            return this;
        }
    
        global QueryRuleSet matchAll() {
            this.matchMode = MATCH_ALL;
            return this;
        }
    
        global void addRule(QueryRule rule) {
            if (rule.parent != null) {
                configError(rule, 'Sub-Rule cannot be reparented');
            } else if (rule.isRoot == true) {
                configError(rule, 'Root-Rule cannot be reparented');
            }
            QueryRule root = getRoot();
            root.isRoot = true;
            rule.parent = this;
            rule.isRoot = false;
            subRules.add(rule);
            // TODO: this next bit of logic is too highly-coupled to the child QueryRule types, for my liking:
            if (rule instanceof MetadataRule) {
                root.registerMetadata((MetadataRule) rule);
            } else if (rule instanceof FromClauseTarget) {
                root.registerTargetType(((FromClauseTarget) rule).targetType);
            }
        }
    
        global QueryRuleSet whereClauseRequired() {
            addRule(new WhereClauseRequired());
            return this;
        }
    
        global QueryRuleSet fromClauseTarget(Schema.SObjectType targetType) {
            addRule(new FromClauseTarget(targetType));
            return this;
        }
    
        global QueryRuleSet subRules() {
            QueryRuleSet newSubRules = new QueryRuleSet();
            addRule(newSubRules);
            return newSubRules;
        }
    
        global QueryRuleSet metadataRule(String targetName) {
            return metadataRule(null, targetName);
        }
    
        global QueryRuleSet metadataRule(Schema.SObjectType targetType, String targetName) {
            targetType = registerOrGetTargetType(targetType, String.isBlank(targetName) ? 'Metadata-Driven Search Terms' : targetName);
            addRule(new MetadataRule(targetType, targetName));
            return this;
        }

        global RestrictedSearchTermsRule startSearchTerms() {
            return startSearchTerms(null, null);
        }

        global RestrictedSearchTermsRule startSearchTerms(String ruleName) {
            return startSearchTerms(null, ruleName);
        }

        global RestrictedSearchTermsRule startSearchTerms(Schema.SObjectType targetType, String ruleName) {
            ruleName = String.isNotBlank(ruleName) ? ruleName : 'Inline Search Terms';
            targetType = registerOrGetTargetType(targetType, ruleName);
            RestrictedSearchTermsRule searchTerms = new RestrictedSearchTermsRule(targetType, ruleName);
            addRule(searchTerms);
            return searchTerms;
        }

        private Schema.SObjectType registerOrGetTargetType(Schema.SObjectType targetType, String ruleName) {
            QueryRule root = getRoot();
            if (targetType != null) {
                root.registerTargetType(targetType);
            } else {
                targetType = root.registeredTargetType;
            }
            if (targetType == null) {
                configError(this, 'Cannot add type-specific rule [' + ruleName + 
                    '] without specifying a target type');
            }
            return targetType;
        }
        
        global override void assert(SOQLParser.SOQL soql) {
            Boolean matchedAll = true;
            RuleViolationException lastViolation;
            for (QueryRule subRule : subRules) {
                try {
                    subRule.assert(soql);
                    // "Any" mode is done upon 1st success:
                    if (matchMode == MATCH_ANY) {
                        return;
                    }
                } catch (RuleViolationException err) {
                    matchedAll = false;
                    lastViolation = err;
                    if (matchMode == MATCH_ALL) {
                        break;
                    }
                }
            }
    
            if (lastViolation != null) {
                throw lastViolation;
            }
        }
    }
}