/*
* Mike Ulveling
*
* Don't touch this code if you're not me.
*
* !! See here for documention of usage and features:
* https://jira-stars.atlassian.net/wiki/spaces/~557058059effa53d514c58a5b7d64f49153424/pages/2576678921/SOQLParser
*
* Description:
* Bottom-up expression parser for very efficient parsing of SOQL condition expressions (recursive-descent parsing of infix expressions is
* inefficient, and its performace degrades drastically as levels of precedence are added to an expression language). The supported syntax here
* is a relaxed version (i.e. ideally a superset) of strict SOQL syntax, however note that the supplied serializer will always output any
* parseable expression into strict SOQL syntax. Various processing modules (including serialization) are implemented via the Visitor pattern,
* which is definitely not-so-efficient but results in very clean code.
*
* See here for Salesforce's docs on SOQL WHERE clause features:
* https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select_conditionexpression.htm
*
* See here for a rough-draft of SOQL Grammar (note: this is out of date as it doesn't express Aggregation queries, but for WHERE conditions it's
* a decent reference, other than Math Expressions being wrong):
* http://blog.jeffdouglas.com/2009/09/23/syntax-rules-for-soql/
*/
global class SOQLParser {

    global virtual class ErrorException extends Exception {}
    global class ParseException extends ErrorException {}
    global class ReferenceException extends ErrorException {}
    global class TypeException extends ErrorException {}
    global class SerializerException extends ErrorException {}
    global class EvaluationException extends ErrorException {}
    
    global static String getErrorType(ErrorException err) {
        if (err instanceof ParseException) {
            return 'SyntaxError';
        } else if (err instanceof ReferenceException) {
            return 'ReferenceError';
        } else if (err instanceof TypeException) {
            return 'TypeError';
        } else if (err instanceof SerializerException) {
            return 'SerializerError';
        } else {
            return 'Error';
        }
    }
    
    global static ErrorException error;
    global static SOQLLexer.Token errorLoc;
    // pairs of startIndex, endIndex that designate the error highlight regions; this array's length must be a multiple of 2:
    global static Integer[] errorHighlights;
    
    // the default parser instance:
    global static SOQLParser P = new SOQLParser();
    
    global static SOQLParser restoreDefaults() {
        return SOQLParser.P = new SOQLParser();
    }
    
    ReferenceProcessor refProc;
    
    // Wrapping the various bindings in an object so that we can make changes to these inner bindings 
    // and have them propagate down to the parent AND child nested SOQL's - because it's now passed by 
    // reference among them all.
    class Bindings {
        Object[] anons = new Object[]{};
        Object[] indexed = new Object[]{};
        Map<String, Object> named = new Map<String, Object>();
    }

    class SelectElmt {
        // Only populated if this select element was parsed from a different source than the main SOQL query,
        // i.e. the SOQL.sel() builder methods:
        SOQLLexer altLexer;
        
        SOQLLexer.Token[] pathToks;
        SOQLLexer.Token[] funcToks;
        // e.g. ".safe.fieldset", ".system"
        String funcsCatLC = '';

        Boolean isSafe() {
            Integer safeIndex = funcsCatLC.indexOf('.safe');
            Integer systemIndex = funcsCatLC.indexOf('.system');
            return safeIndex > systemIndex;
        }

        Boolean isSystem() {
            Integer safeIndex = funcsCatLC.indexOf('.safe');
            Integer systemIndex = funcsCatLC.indexOf('.system');
            return systemIndex > safeIndex;
        }

        Boolean isFieldset() {
            return funcsCatLC.indexOf('.fieldset') > -1;
        }

        Boolean isStarSelector() {
            return pathToks.size() > 0 && pathToks[0].ttype == SOQLLexer.STAR;
        }
    }

    class SortElmt {
        SOQLLexer.Token[] field;
        Boolean nullsLast = false;
        Boolean nullsFirst = false;
        Boolean ascending = false;
        Boolean descending = false;
    }
    
    global static Boolean assertReBindCompatibility(LocalReBindPool x, LocalReBindPool y) {
        if (x == null && y == null) {
            return true;
        }
        return x != null ? x.assertCompatibility(y, false) : y.assertCompatibility(x, true);
    }

    global class LocalReBindPool {
        String name;
        public Integer size = 3;
        public String idVar = 'ids'; // e.g. ids0, ids1, ids2
        public String recVar = 'recs';
        public String strVar = 'strs';

        List<Id[]> idArrays;
        List<sObject[]> recArrays;
        List<String[]> strArrays;

        public LocalReBindPool(String name) {
            this.name = name;
        }

        public LocalReBind accept(Object[] vals) {
            if (vals instanceof sObject[]) {
                if (recArrays == null) {
                    this.recArrays = new List<sObject[]>();
                }
                Integer currentSize = recArrays.size();
                if (currentSize < size) {
                    recArrays.add((sObject[]) vals);
                    return new LocalReBind(this, recVar, currentSize, vals);
                }
            } else if (vals instanceof Id[]) {
                if (idArrays == null) {
                    this.idArrays = new List<Id[]>();
                }
                Integer currentSize = idArrays.size();
                if (currentSize < size) {
                    idArrays.add((Id[]) vals);
                    return new LocalReBind(this, idVar, currentSize, vals);
                }
            } else if(vals instanceof String[]) {
                if (strArrays == null) {
                    this.strArrays = new List<String[]>();
                }
                Integer currentSize = strArrays.size();
                if (currentSize < size) {
                    strArrays.add((String[]) vals);
                    return new LocalReBind(this, strVar, currentSize, vals);
                }
            }
            return null;
        }

        global sObject[] getRecArray(Integer index) {
            if (recArrays != null && index < recArrays.size()) {
                return recArrays[index];
            }
            return null;
        }

        global String[] getStrArray(Integer index) {
            if (strArrays != null && index < strArrays.size()) {
                return strArrays[index];
            }
            return null;
        }

        global Id[] getIdArray(Integer index) {
            if (idArrays != null && index < idArrays.size()) {
                return idArrays[index];
            }
            return null;
        }

        private Boolean assertCompatibility(LocalReBindPool arg, Boolean reverseArgs) {
            if (arg == null || arg.size != size || arg.idVar != idVar || 
                    arg.recVar != recVar || arg.strVar != strVar) {
                if (reverseArgs != true) {
                    System.assert(false, 'Re-bind pool "' + name + '" is not compatible with ' + 
                        (arg != null ? '"' + arg.name + '"' : null));
                } else {
                    System.assert(false, 'Re-bind pool' + (arg != null ? '"' + arg.name + '"' : null) + 
                        ' is not compatible with "' + name + '"');
                }
                return false;
            }
            return true;
        }
    }

    public class LocalReBind {
        public LocalReBindPool pool;
        String var;
        Integer index;
        Object[] vals;

        LocalReBind(LocalReBindPool pool, String var, Integer index, Object[] vals) {
            this.pool = pool;
            this.var = var;
            this.index = index;
            this.vals = vals;
        }

        public String getLocalVar() {
            return var + index;
        }
    }

    global class SOQL {
        @TestVisible
        public SOQLParser parser;
        SOQLLexer lex;

        // staging variables:
        Bindings bindings;
        LocalReBindPool reBindPool;
        String bindTypesMode = null; // "loose", "strict"

        // parsed variables:
        public SelectElmt[] selects = new SelectElmt[]{};
        public SOQL parent; // only nested child queries will have this populated
        public SOQL[] nested; // nested child queries
        public SOQLLexer.Token fromEntity;
        public CondExpr whereCond;
        public SortElmt[] sorts;
        public SOQLLexer.Token limitLiteral;
        public SOQLLexer.Token limitAnon;
        public SOQLLexer.Token limitNamed;
        public SOQLLexer.Token limitIndexed;
        public Boolean forUpdate = false;

        // resolved variables:
        String resSelects;
        public Schema.sObjectType resTable;
        String resFrom; // this will differ from resTable in the case of child nested queries
        String resSorts;
        Integer resLimitRows; // this value can also be staged

        global SOQL(String queryText) {
            this.lex = SOQLLexer.newLexer(queryText);
            this.parser = new SOQLParser();
            this.bindings = new Bindings();
            this.parse();
        }

        private SOQL(SOQL parent, SOQLLexer lex) {
            this.parent = parent;
            this.lex = lex;
            // Nested child soql parser:
            this.parser = new SOQLParser();
            parser.refProc = new ReferenceProcessor(parent.parser.refProc);
        }

        global SOQL forUpdate(Boolean queryForUpdate) {
            this.forUpdate = queryForUpdate == true;
            return this;
        }

        global SOQL bindTypesMode(String mode) {
            this.bindTypesMode = mode;
            return this;
        }

        global CondExpr getWhereCondition() {
            return whereCond;
        }

        global String getFromLexeme() {
            return fromEntity != null ? fromEntity.lexeme : null;
        }

        global Schema.SObjectType getFromTarget() {
            Assert.isNotNull(resTable, 'FROM target cannot be requested before SOQL has been resolved');
            return resTable;
        }

        global SOQL reBindPool(LocalReBindPool reBindPool) {
            this.reBindPool = reBindPool;
            return this;
        }

/* mulveling-dev

        global SOQL reBindPool(String name) {
            this.reBindPool = new LocalReBindPool(name);s
            return this;
        }

        global sObject[] getReBindRecArray(Integer index) {
            return reBindPool != null ? reBindPool.getRecArray(index) : null;
        }

        global String[] getReBindStrArray(Integer index) {
            return reBindPool != null ? reBindPool.getStrArray(index) : null;
        }

        global Id[] getReBindIdArray(Integer index) {
            return reBindPool != null ? reBindPool.getIdArray(index) : null;
        }

        global SOQL sel(String selPaths) {
            SOQLLexer altLexer = SOQLLexer.newLexer(selPaths);
            parseSelectList(altLexer, null, null);
            return this;
        }

        global SOQL safeSel(String selPaths) {
            SOQLLexer.Token func = newInjectedToken(SOQLLexer.KW_SAFE, 'SAFE');
            SOQLLexer altLexer = SOQLLexer.newLexer(selPaths);
            parseSelectList(altLexer, func, null);
            return this;
        }

        global SOQL systemSel(String selPaths) {
            SOQLLexer.Token func = newInjectedToken(SOQLLexer.KW_SYSTEM, 'SYSTEM');
            SOQLLexer altLexer = SOQLLexer.newLexer(selPaths);
            parseSelectList(altLexer, func, null);
            return this;
        }

        global SOQL val(Object anonVal) {
            bindings.anons.add(anonVal);
            bindings.indexed.add(anonVal);
            return this;
        }

        global SOQL val(Object a1, Object a2) {
            bindings.anons.addAll(new Object[]{ a1, a2 });
            bindings.indexed.addAll(new Object[]{ a1, a2 });
            return this;
        }

        global SOQL val(Object a1, Object a2, Object a3) {
            bindings.anons.addAll(new Object[]{ a1, a2, a3 });
            bindings.indexed.addAll(new Object[]{ a1, a2, a3 });
            return this;
        }

        global SOQL val(Object a1, Object a2, Object a3, Object a4) {
            bindings.anons.addAll(new Object[]{ a1, a2, a3, a4 });
            bindings.indexed.addAll(new Object[]{ a1, a2, a3, a4 });
            return this;
        }

        global SOQL val(Object a1, Object a2, Object a3, Object a4, Object a5) {
            bindings.anons.addAll(new Object[]{ a1, a2, a3, a4, a5 });
            bindings.indexed.addAll(new Object[]{ a1, a2, a3, a4, a5 });
            return this;
        }

        global SOQL val(Object a1, Object a2, Object a3, Object a4, Object a5, Object a6) {
            bindings.anons.addAll(new Object[]{ a1, a2, a3, a4, a5, a6 });
            bindings.indexed.addAll(new Object[]{ a1, a2, a3, a4, a5, a6 });
            return this;
        }
        */

        global SOQL vals(Map<String, Object> named) {
            if (named != null) {
                bindings.named.putAll(named);
            }
            return this;
        }

        global SOQL vals(Object[] indexed) {
            if (indexed != null) {
                bindings.anons.addAll(indexed);
                bindings.indexed.addAll(indexed);
            }
            return this;
        }

/* mulveling-dev
        global Integer systemCount() {
            resolve(false);
            bind();
            return RKSecurity.SystemSharingModel.countQuery(ser(true), this.reBindPool);
        }

        global Integer safeCount() {
            resolve(true);
            bind();
            return RKSecurity.SystemSharingModel.countQuery(ser(true), this.reBindPool);
        }

        global sObject[] systemQuery() {
            resolve(false);
            bind();
            return RKSecurity.SystemSharingModel.query(ser(false), this.reBindPool);
        }

        // Applies CRUS and FLS, as well as the record security models specified by RKSecurity.SafeSharingModel: 
        global sObject[] safeQuery() {
            return safeQuery(RKSecurity.SafeSharingModel);
        }

        // Applies CRUS and FLS, but defers record security to the RKShare implementation specified by the 
        // sharingModel argument: 
        public sObject[] safeQuery(RKShare.SecurityModel sharingModel) {
            resolve(true);
            bind();
            return sharingModel.query(ser(false), this.reBindPool);
        }

        // Works like safeQuery, except additionally passes query results through RKSecurity.filterSObject for the 
        // application of RKMock alias mappings:
        global List<Map<String, Object>> clientQuery() {
            return clientQuery(RKSecurity.SafeSharingModel);
        }

        public List<Map<String, Object>> clientQuery(RKShare.SecurityModel sharingModel) {
            // Note that we bypass "safe" mode for the parse & resolve, because it will be finally enforced by the 
            // subsequent RKSecurity.filterSObjectSafeReadables call, and this way we save CPU cycles:
            resolve(false);
            bind();
            return RKSecurity.filterSObjectSafeReadables(sharingModel.query(ser(false), this.reBindPool));
        }

        global Database.QueryLocator getSystemQueryLocator() {
            resolve(false);
            bind();
            return RKSecurity.SystemSharingModel.getQueryLocator(ser(false), this.reBindPool);
        }

        global Database.QueryLocator getSafeQueryLocator() {
            return getSafeQueryLocator(RKSecurity.SafeSharingModel);
        }

        public Database.QueryLocator getSafeQueryLocator(RKShare.SecurityModel sharingModel) {
            resolve(true);
            bind();
            return sharingModel.getQueryLocator(ser(false), this.reBindPool);
        }
        */

        public SOQL resolve(Boolean safeModeDefault) {
            // This is a parent (root) query if this.parent is null:
            if (parent == null) {

/* mulveling-dev
                this.resTable = RKMock.resolveObject(fromEntity.lexeme);
                if (resTable == null) {
                    this.resTable = RKSecurity.resolveSObjectTypeOrThrow(fromEntity.lexeme);
                }
*/
                this.resTable = RKSecurity.resolveSObjectTypeOrThrow(fromEntity.lexeme);

                this.resFrom = '' + resTable;

            // Else this is a child nested query:
            } else {
/* mulveling-dev
                Schema.ChildRelationship childRel = RKMock.resolveChildRelFromParent(parent.resTable, fromEntity.lexeme);
                if (childRel == null) {
                    childRel = RKSecurity.resolveChildRelFromParentOrThrow(parent.resTable, fromEntity.lexeme);
                }
*/
                Schema.ChildRelationship childRel = RKSecurity.resolveChildRelFromParentOrThrow(parent.resTable, fromEntity.lexeme);

                this.resTable = childRel.getChildSObject();
                this.resFrom = childRel.getRelationshipName();
            }
            if (safeModeDefault == true) {
                RKSecurity.assertReadable(resTable);
            }
            this.parser.refProc.baseRefType = resTable;
            this.parser.refProc.strictRefs = true;

            Map<String, RKSecurity.PathPart> selPathsMap = getSelectPathsMap(safeModeDefault);
            if (selPathsMap.isEmpty()) {
                selPathsMap.put('Id', null);
            }
            this.resSelects = String.join(new List<String>(selPathsMap.keySet()), ',');

            // ORDER BY processing to set this.resSorts:
            if (this.sorts != null) {
                String[] sortParts = new String[]{};
                for (SortElmt elmt : sorts) {
                    Map<String, RKSecurity.PathPart> resPathMap = getPathsMap(new List<SOQLLexer.Token[]>{ elmt.field }, safeModeDefault == true); //elmt.safeMode);
                    // We only passed in a single field path, so the returned map's keySet() should have at most 1 element:
                    String[] resPathKey = new List<String>(resPathMap.keySet());
                    if (resPathKey.size() > 0) {
                        RKSecurity.PathPart pathTail = resPathMap.get(resPathKey[0]);
                        if (pathTail != null) {
                            SOQLLexer.Token fieldTermTok = elmt.field[elmt.field.size() - 1];
                            if (pathTail.fieldDesc != null) {
                                if (pathTail.fieldDesc.isSortable()) {
                                    sortParts.add(resPathKey[0] + (elmt.ascending ? ' ASC' : '') + (elmt.descending ? ' DESC' : '') + 
                                            + (elmt.nullsLast ? ' NULLS LAST' : '') + (elmt.nullsFirst ? ' NULLS FIRST' : ''));
                                } else {
                                    parseErr(fieldTermTok, 'ORDER BY field ' + fieldTermTok.lexeme + ' is not sortable');
                                }
                            } else {
                                parseErr(fieldTermTok, 'ORDER BY target ' + fieldTermTok.lexeme + ' is not a field');
                            }
                        }
                    }
                }
                this.resSorts = String.join(sortParts, ',');
            }

            // Recursively resolve child nested queries:
            if (nested != null) {
                for (SOQL child : nested) {
                    child.resolve(safeModeDefault);
                }
            }

            return this;
        }

        // Resolves all field references in the WHERE clauses of this SOQL (including nested child queries).
        // Does NOT process parameterized value bindings - use bind() if you need that (bind() will also resolve references). 
        public SOQL resolveWhereClauseReferences() {
            // !! This bind() method is not recursive; we flatten the parent and child soqls into one list for 
            // iterative processing:
            final SOQL parent = this;
            SOQL[] bindSOQLs = new SOQL[]{};
            if (parent.nested != null) {
                bindSOQLs.addAll(parent.nested);
            }
            bindSOQLs.add(parent);
            for (SOQL soql : bindSOQLs) {
                ReferenceProcessor refProc = soql.parser.refProc;
                CondExpr cond = soql.whereCond;
                //Bindings bindings = soql.bindings;
                if (cond != null) {
                    cond.traverse(refProc);
                }
            }
            return this;
        }

        // Resolves all field references in the WHERE clauses of this SOQL (including nested child queries), AND binds
        // parameterized values.
        public SOQL bind() {
            ValueResolver valRex;
            // !! This bind() method is not recursive; we flatten the parent and child soqls into one list for 
            // iterative processing:
            final SOQL parent = this;
            SOQL[] bindSOQLs = new SOQL[]{};
            if (parent.nested != null) {
                bindSOQLs.addAll(parent.nested);
            }
            bindSOQLs.add(parent);
            // !! Note we also apply the parent soql's bindings for all nested child soqls. We clone a working 
            // copy of the this.bindings.anons list because we will mutate (shift) the working copy as 
            // anonymous values are consumed: 
            Object[] anonBindsCopy = parent.bindings.anons.clone();
            Integer anonCursor = 0;
            for (SOQL soql : bindSOQLs) {
                switch on (bindTypesMode) {
                    when 'loose' {
                        soql.parser.paramBindLoose();
                    }
                    when 'strict' {
                        soql.parser.paramBindStrict();
                    }
                }
                ReferenceProcessor refProc = soql.parser.refProc;
                CondExpr cond = soql.whereCond;
                //Bindings bindings = soql.bindings;
                if (cond != null) {
                    cond.lastUnboundAnonParams = null;
                    cond.traverse(refProc);
                    // This 1st traversal is just to clear out (clobber) bindings from prior runs:
                    cond.traverse(new ValueResolver(new Map<String, Object>())
                        .refProc(refProc)
                        .normalizeNamedParams()
                        .clobberPriorAndAnons(true));

                    ValueResolver valRez;
                    cond.traverse(valRez = new ValueResolver(anonBindsCopy)
                        .refProc(refProc)
                        .reBindPool(this.reBindPool));
                    arrayShift(anonBindsCopy, valRez.anonCounter);
                    // Check whether any anonymous parameters remain unbound; this is a parse error:
                    if (cond.lastUnboundAnonParams != null && cond.lastUnboundAnonParams.size() > 0) {
                        parseErr(cond.lastUnboundAnonParams[0], 
                            'Anonymous parameter must be bound to a value before query execution');
                    }

                    if (!parent.bindings.named.isEmpty()) {
                        cond.traverse(new ValueResolver(parent.bindings.named)
                            .refProc(refProc)
                            .reBindPool(this.reBindPool)
                            .normalizeNamedParams());
                    }
                    if (!parent.bindings.indexed.isEmpty()) {
                        cond.traverse(new ValueResolver(parent.bindings.indexed)
                            .refProc(refProc)
                            .reBindPool(this.reBindPool));
                    }
                    //if (refProc.baseRefType != null && refProc.strictRefs == true) {
                    //    cond.traverse(refProc);
                    //}
                }
                soql.resLimitRows = null;
                Object limitVal;
                SOQLLexer.Token limitTok;
                if (soql.limitLiteral != null) {
                    limitTok = soql.limitLiteral;
                    limitVal = Decimal.valueOf(soql.limitLiteral.lexeme);
                } else if (soql.limitNamed != null) {
                    limitTok = soql.limitNamed;
                    String matchKey;
                    if (bindings.named != null) {
                        for (String key : bindings.named.keySet()) {
                            if (key == soql.limitNamed.lexeme) {
                                matchKey = key;
                                limitVal = bindings.named.get(key);
                                break;
                            }
                        }
                    }
                    if (matchKey == null) {
                        parseErr(soql.limitNamed, 
                            'LIMIT binding :' + soql.limitNamed.lexeme + ' must be bound before query execution');
                    }
                } else if (soql.limitAnon != null) {
                    limitTok = soql.limitAnon;
                    if (anonBindsCopy.size() > 0) {
                        limitVal = arrayShift(anonBindsCopy, 1);
                    } else {
                        parseErr(soql.limitAnon, 
                            'Anonymous LIMIT must be bound to a value before query execution');
                    }
                } else if (soql.limitIndexed != null) {
                    Integer index = Decimal.valueOf(soql.limitIndexed.lexeme).intValue();
                    if (parent.bindings.indexed != null && parent.bindings.indexed.size() > index) {
                        limitVal = parent.bindings.indexed[index];
                    } else {
                        parseErr(soql.limitIndexed, 'LIMIT index-bound value :' + index + ' was not supplied');
                    }
                }

                if (limitVal != null) {
                    if (!(limitVal instanceof Decimal)) {
                        parseErr(limitTok, 
                            'LIMIT value must an integer; got ' + limitVal);
                    }
                    Decimal dlmt = (Decimal) limitVal;
                    if (dlmt.intValue() != dlmt) {
                        parseErr(limitTok, 
                            'LIMIT value must be an integer; got ' + limitVal);
                    }
                    soql.resLimitRows = dlmt.intValue();
                    if (soql.resLimitRows < 1) {
                        parseErr(limitTok, 
                            'LIMIT value cannot be less than 1; got ' + limitVal);
                    }
                }
            }

            return this;
        }

        global String ser() {
            return ser(false);
        }

        // !! resolve() and bind() should be called before ser():
        global String ser(Boolean countOnly) {
            String[] nestedSer = new String[]{};
            if (!countOnly) {
                if (nested != null) {
                    for (SOQL child : nested) {
                        nestedSer.add('(' + child.ser(false) + ')');
                    }
                }
            }
            String ser;
            if (countOnly) {
                ser = 'SELECT count()';
            } else {
                ser = 'SELECT ' + resSelects + (nestedSer.size() > 0 ? ',' + String.join(nestedSer, ',') : '');
            }
            ser += ' FROM ' + resFrom;
            if (whereCond != null) {
                ser += ' WHERE ' + whereCond.ser();
            }
            if (resSorts != null) {
                ser += ' ORDER BY ' + resSorts;
            }
            if (resLimitRows != null) {
                ser += ' LIMIT ' + resLimitRows;
            }
            if (forUpdate == true && parent == null) {
                ser += ' FOR UPDATE';
            }
            return ser;
        }

        // !! The PathParts returned will point to the terminating fields (i.e. leaves), but the head of compound references 
        // can always be accessed via PathPart.head:
        private Map<String, RKSecurity.PathPart> getSelectPathsMap(Boolean safeModeDefault) {
            Map<String, RKSecurity.PathPart> pathsMap = new Map<String, RKSecurity.PathPart>();
            Integer selectsIndex = 0;
            Integer selectsLen = this.selects.size();
            while (selectsIndex < selectsLen) {
                String[] sels = new String[]{};
                Boolean safeModeForChunk = null;
                SelectElmt starSelectorElmt = null;
                for (; selectsIndex < selectsLen; selectsIndex++) {
                    SelectElmt elmt = this.selects[selectsIndex];
                    Boolean safeModeForElmt = safeModeDefault == true;
                    if (elmt.isSafe()) {
                        safeModeForElmt = true;
                    } else if (elmt.isSystem()) {
                        safeModeForElmt = false;
                    }
                    // At the start of a new chunk (i.e. each call to RKSecurity.selectMapLogic), we set the chunk's overall
                    // security mode to that of the 1st select element:
                    if (safeModeForChunk == null) {
                        safeModeForChunk = safeModeForElmt;
                    // A change in the calculated safe mode, from one element to the next, causes us to begin a new "chunk", 
                    // since each RKSecurity.selectMapLogic call takes an overall security mode setting, so we must keep each
                    // chunk homogenous:
                    } else if (safeModeForChunk != safeModeForElmt) {
                        break;
                    }

                    if (elmt.isStarSelector()) {
                        starSelectorElmt = elmt;
                    } else {
                        String[] parts = new String[]{};
                        for (SOQLLexer.Token partTok : elmt.pathToks) {
                            parts.add(partTok.lexeme);
                        }
                        sels.add(String.join(parts, '.'));
                    }
                }

                if (sels.size() > 0) {
                    pathsMap.putAll(RKSecurity.selectMapLogic(safeModeForChunk, false, this.resTable, sels, null));
                }
                if (starSelectorElmt != null) {
                    pathsMap.putAll(RKSecurity.selectStarLogic(safeModeForChunk, this.resTable));
                }
            }
            return pathsMap;
        }

        // !! The PathParts returned will point to the terminating fields (i.e. leaves), but the head of compound references 
        // can always be accessed via PathPart.head:
        private Map<String, RKSecurity.PathPart> getPathsMap(List<SOQLLexer.Token[]> tokenizedPaths, Boolean safeSelectMode) {
            String[] selElmts = new String[]{};
            for (SOQLLexer.Token[] tokPath : tokenizedPaths) {
                String[] parts = new String[]{};
                for (SOQLLexer.Token tokPart : tokPath) {
                    parts.add(tokPart.lexeme);
                }
                selElmts.add(String.join(parts, '.'));
            }
            if (selElmts.size() > 0) {
                // selectLogic(Boolean isSafeMode, Boolean crudCheck, Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy)
                return RKSecurity.selectMapLogic(safeSelectMode, false, this.resTable, selElmts, null);
            } else {
                return new Map<String, RKSecurity.PathPart>();
            }
        }

        private SOQL parse() {
            SOQLLexer.Token[] toks = lex.toks;
            SOQLLexer.Token tok;
            Integer peek = toks[lex.next].ttype;
            if (peek != SOQLLexer.KW_SELECT && peek != SOQLLexer.KW_FROM) {
                mismatch(toks[lex.next], 'Expected query to begin with SELECT or FROM clause');
            }

            Boolean gotClause = false;
            do {
                peek = toks[lex.next].ttype;
                if (peek == SOQLLexer.KW_SELECT) {
                    lex.next++; // consume and discard SELECT
                    this.parseSelectList(null, null, null);
                    gotClause = true;

                } else if (peek == SOQLLexer.KW_FROM) {
                    if (this.fromEntity != null) {
                        parseErr(toks[lex.next], 'Duplicate FROM clause not allowed');
                    }
                    lex.next++; // consume and discard FROM
                    tok = toks[lex.next++]; // consume next token, which should be a NAME
                    if (!isIdentifierTok(tok)) {
                        mismatch(tok, 'Expected FROM clause to specify an entity table name');
                    }
                    this.fromEntity = tok;
                    gotClause = true;

                } else if (peek == SOQLLexer.KW_WHERE) {
                    if (this.whereCond != null) {
                        parseErr(toks[lex.next], 'Duplicate WHERE clause not allowed');
                    }
                    lex.next++; // consume and discard WHERE
                    // Allow a non-EOF token to exist after the cond-expression parse is finished:
                    final Boolean dontMatchEOF = false;
                    this.whereCond = parseCondExpr(parser, lex, 0, dontMatchEOF).alwaysSpreadBindArrayElmts(false);
                    gotClause = true;

                } else if (peek == SOQLLexer.KW_ORDER) {
                    if (sorts != null) {
                        parseErr(toks[lex.next], 'Duplicate ORDER BY clause not allowed');
                    }
                    lex.next++; // consume and discard ORDER
                    tok = toks[lex.next++];
                    if (!isIdentifierTok(tok, 'BY')) {
                        mismatch(tok, 'Expected ORDER BY clause');
                    }
                    this.parseSortList();
                    gotClause = true;

                } else if (isIdentifierTok(toks[lex.next], 'FOR')) {
                    lex.next++; // consume and discard FOR
                    tok = toks[lex.next++];
                    if (!isIdentifierTok(tok, 'UPDATE')) {
                        mismatch(tok, 'Expected FOR UPDATE query modifier');
                    }
                    this.forUpdate = true;
                    gotClause = true;

                // Note that LIMIT has not been designated as a keyword:
                } else if (isIdentifierTok(toks[lex.next], 'LIMIT')) {
                    lex.next++; // consume and discard LIMIT
                    tok = toks[lex.next++];
                    if (tok.ttype == SOQLLexer.DECIMAL_NUMBER) {
                        Decimal lmt = Decimal.valueOf(tok.lexeme);
                        if (lmt < 1) {
                            parseErr(tok, 'LIMIT value cannot be less than 1');
                        } else if (lmt - lmt.intValue() != 0) {
                            parseErr(tok, 'LIMIT value must be an integer');
                        } else {
                            this.limitLiteral = tok;
                        }
                    } else if (tok.ttype == SOQLLexer.QUEST_MARK) {
                        this.limitAnon = tok;
                    } else if (tok.ttype == SOQLLexer.COLON) {
                        tok = toks[lex.next++];
                        if (isIdentifierTok(tok)) {
                            this.limitNamed = tok;
                        } else if (tok.ttype == SOQLLexer.DECIMAL_NUMBER) {
                            this.limitIndexed = tok;
                            Decimal lmt = Decimal.valueOf(tok.lexeme);
                            if (lmt.intValue() != lmt || lmt < 1) {
                                mismatch(tok, 'LIMIT binding after colon must be a name or a positive integer index');
                            }
                        } else {
                            mismatch(tok, 'Expected named binding after colon');
                        }
                    } else {
                        mismatch(tok, 'Expected literal number or binding in LIMIT clause');
                    }
                    gotClause = true;

                // Note that GROUP has not been designated as a keyword becasue of its potential conflict 
                // with that entity:
                } else if (isIdentifierTok(toks[lex.next], 'GROUP')) {
                    SOQLLexer.Token groupTok = toks[lex.next++]; // consume GROUP
                    tok = toks[lex.next++];
                    if (!isIdentifierTok(tok, 'BY')) {
                        mismatch(tok, 'Expected GROUP BY clause');
                    }
                    parseErr(groupTok, 'GROUP BY clauses are not currently supported in SOQLParser');

                // Note that HAVING has not been designated as a keyword:
                } else if (isIdentifierTok(toks[lex.next], 'HAVING')) {
                    parseErr(toks[lex.next], 'HAVING clauses are not currently supported in SOQLParser');

                } else if (peek == SOQLLexer.EOF) {
                    tok = toks[lex.next];
                    if (fromEntity == null) {
                        parseErr(tok, 'SOQL requires a FROM clause');
                    } else {
                        break; // done! successful parse
                    }

                } else if (peek == SOQLLexer.ERROR) {
                    tok = toks[lex.next];
                    parseErr(tok, (gotClause ? 'Dangling ' : 'Lead ') + 
                        tok.lexeme +  ' is not a legal SOQL character');
                } else {
                    tok = toks[lex.next];
                    // If we finished parsing a child nested query then we allow termination on a next close-paren ')':
                    if (parent != null && tok.ttype == SOQLLexer.CLOSE_PAREN) {
                        break;
                    }
                    //parseErr(toks[lex.next], (gotClause ? 'Dangling ' : 'Lead ') + 
                    //    tok.lexeme + ' is not a legal SOQL clause start' + (gotClause ? ' or continuation' : ''));
                    if (gotClause) {
                        parseErr(toks[lex.next], 'Dangling ' + tok.lexeme + ' is not a legal continuation');
                    } else {
                        parseErr(toks[lex.next], 'Lead ' + tok.lexeme + ' is not a legal start');
                    }
                }
            } while (true);

            return this;
        }

        private void parseSelectList(SOQLLexer altLexer, SOQLLexer.Token func, SOQLLexer.Token nestedFunc) {
            SOQLLexer lex = altLexer != null ? altLexer : this.lex;
            SOQLLexer.Token[] toks = lex.toks;
            SOQLLexer.Token tok, newFunc;
            Integer peek;
            // We allow continuation automatically at the start, but after an element is parsed only a subsequent 
            // comma will allow continuation:
            Boolean allowContinue = true;
            do {
                peek = toks[lex.next].ttype;

                // Consume any run of commas; if at lest 1 comma is consumed then allow continuation of this select list:
                if (peek == SOQLLexer.COMMA) {
                    // Commas allow us to continue parsing additional elements in the select list - and this prevents
                    // us from consuming clause keywords like FROM, WHERE, etc as select-able elements:
                    allowContinue = true;
                    // We allow any run of multiple commas:
                    do {
                        peek = toks[lex.next].ttype;
                        if (peek == SOQLLexer.COMMA) {
                            lex.next++; // consume and discard the comma
                        } else {
                            break;
                        }
                    } while(true); // keep discarding commas as long as we find them in sequence

                    // Update the peek token to the 1st token after the last comma we consumed:
                    peek = toks[lex.next].ttype;
                }

                if (allowContinue) {
                    // Allow continuation for this next element, but a subsequent comma will be required for any continuation
                    // after that: 
                    allowContinue = false;
                } else {
                    // If continuation is not allowed then no more select elements; we're done
                    break;
                }

                if (peek == SOQLLexer.STAR) {
                    SOQLLexer.Token starToken = toks[lex.next++]; // consume the "*" token
                    addSelectableEntity(altLexer, new SOQLLexer.Token[]{ starToken }, func, nestedFunc);
                
                // Nested queries start with an open-parenthesis:
                } else if (peek == SOQLLexer.OPEN_PAREN) {
                    lex.next++; // consume and discard open-paren
                    peek = toks[lex.next].ttype;
                    if (peek != SOQLLexer.KW_SELECT && peek != SOQLLexer.KW_FROM) {
                        mismatch(toks[lex.next], 'Expected nested child query to begin with SELECT or FROM clause');
                    }
                    if (this.parent != null) {
                        parseErr(toks[lex.next], 'Child queries cannot be nested more than 1-level deep');
                    }

                    SOQL child = new SOQL(this, lex);
                    if (this.nested == null) {
                        this.nested = new SOQL[]{};
                    }
                    nested.add(child);
                    child.parse();

                    tok = toks[lex.next++];
                    if (tok.ttype != SOQLLexer.CLOSE_PAREN) {
                        mismatch(toks[lex.next], 'Expected parenthetical close ) to complete nested child query');
                    }

                // SELECTable function, e.g. SAFE(), SYSTEM(), FIELDSET():
                } else if (isSelectableFunc(peek)) {
                    tok = toks[lex.next++]; // consume the function name
                    newFunc = tok;
                    if (nestedFunc != null) {
                        parseErr(newFunc, 'Functions cannot be nested 2-deep: ' + 
                            func.lexeme + '(' + nestedFunc.lexeme + '(' + newFunc.lexeme + '()))');
                    } else if (func != null && 
                            newFunc.ttype == SOQLLexer.KW_FIELDSET && func.ttype != SOQLLexer.KW_SAFE && func.ttype != SOQLLexer.KW_SYSTEM) {
                        parseErr(newFunc, 'FIELDSET function can only be nested in SAFE() or SYSTEM(); got: ' + 
                            func.lexeme + '(' + newFunc.lexeme + '())');
                    }
                    tok = toks[lex.next++]; // match open paren
                    if (tok.ttype != SOQLLexer.OPEN_PAREN) {
                        mismatch(tok, 'Expected parenthetical-group open ( after ' + newFunc.lexeme + ' function');
                    }
                    if (func != null) {
                        parseSelectList(altLexer, func, newFunc);
                    } else {
                        parseSelectList(altLexer, newFunc, null);
                    }
                    tok = toks[lex.next++]; // match close paren
                    if (tok.ttype != SOQLLexer.CLOSE_PAREN) {
                        mismatch(tok, 'Expected parenthetical-group close ) to complete ' + newFunc.lexeme + ' function');
                    }

                // SELECTable list, starting in an entity (non-function) name:
                } else if (isIdentifierTok(peek)) {
                    // Compound references will have more than one part:
                    SOQLLexer.Token[] parts = new SOQLLexer.Token[]{};
                    do {
                        // Here we can always assume we're on a NAME (or a KW_* that can act as an identifier) - whether as the 
                        // start or by a dot-op continuation, consume it and add to the parts list:
                        tok = toks[lex.next++]; // consume the NAME or KW_*
                        parts.add(tok);
                        // Peek at the next token after NAME or KW_*:
                        peek = toks[lex.next].ttype;
                        // If we have a dot-operator after the last part, then consume it and expect a NAME after it:
                        if (peek == SOQLLexer.DOT) {
                            lex.next++; // consume the dot-op
                            peek = toks[lex.next].ttype;
                            // ensure the next token is an entity name:
                            if (!isIdentifierTok(peek)) {
                                mismatch(toks[lex.next], 'Expected entity name to follow dot-operator');
                            } else {
                                continue;
                            }
                        
                        // TODO: can we determine whether an open-paren following a field entity is a nested child query
                        // without a separating comma, or an unrecognized function call? That would help up craft a better 
                        // error message... 
                        } else if (peek == SOQLLexer.OPEN_PAREN) {
                            tok = toks[lex.next]; // the open-paren token
                            String funcName = parts[parts.size() - 1].lexeme;
                            // If the open paren follows a known aggregate function name, then we can be pretty sure it was
                            // intended as a function call:
                            if (parts.size() == 1 && (funcName == 'SUM' || funcName == 'AVG' || 
                                    funcName == 'MIN' || funcName == 'MAX' || funcName == 'COUNT')) {
                                parseErr(parts[0], funcName + ' function is not yet supported by SOQLParser');
                            } else {
                                parseErr(tok, 'Selected entity ' + (parts.size() > 1 ? '.' : '') + 
                                    funcName + ' cannot be invoked as a function');
                                //// Break out as if we're done with this entity parse - in case this dangling open paren is 
                                //// the start of a nested child query without a separating comma, which we'll allow:
                                //break;
                            }

                        } else {
                            break;
                        }
                    } while (true);
                    addSelectableEntity(altLexer, parts, func, nestedFunc);

                // COMMAs are simply discarded, regardless of whether they are lead, trailing, repeat, or proper punctuation:
                } else {
                    // As soon as we hit a token that can't be absorbed into this SELECT-list, we're done - it's the 
                    // caller's job to determine whether that next token is something it wants to handle or throw an 
                    // error on...
                    break;
                }
            } while (true);
        }

        void parseSortList() {
            this.sorts = new SortElmt[]{};
            SortElmt activeSort;
            SOQLLexer.Token[] toks = lex.toks;
            SOQLLexer.Token tok;
            Integer peek;
            // 0 => parse path, 1 => parse modifiers, -1 => done
            Integer state = 0;
            do {
                peek = toks[lex.next].ttype;
                if (state == 0 && isIdentifierTok(peek)) {
                    state = 1;
                    // compound references will have more than one part:
                    SOQLLexer.Token[] parts = new SOQLLexer.Token[]{};
                    do {
                        // here we can always assume we're on a NAME - whether as the start or by a dot-op continuation; 
                        // consume it and add to the parts list:
                        tok = toks[lex.next++];
                        parts.add(tok);
                        peek = toks[lex.next].ttype;
                        // if we have a dot-operator after the last part, then consume it and expect a NAME after it:
                        if (peek == SOQLLexer.DOT) {
                            lex.next++; // consume the dot-op
                            peek = toks[lex.next].ttype;
                            // ensure the next token is an entity name:
                            if (!isIdentifierTok(peek)) {
                                mismatch(toks[lex.next], 'Expected entity name to follow dot-operator');
                            } else {
                                continue;
                            }
                        } else {
                            break;
                        }
                    } while (true);
                    
                    activeSort = new SortElmt();
                    activeSort.field = parts;
                    this.sorts.add(activeSort);

                } else if (state == 1 && peek == SOQLLexer.KW_NULLS) {
                    SOQLLexer.Token nullsTok = toks[lex.next++]; // consume NULLS
                    tok = toks[lex.next++];
                    if (tok.ttype != SOQLLexer.KW_LAST && tok.ttype != SOQLLexer.KW_FIRST) {
                        mismatch(tok, 'Expected ' + nullsTok.lexeme + ' FIRST or ' + nullsTok.lexeme + ' LAST modifier');
                    } else if (activeSort == null) {
                        parseErr(tok, 'Lead ' + nullsTok.lexeme + ' ' + tok.lexeme + 
                            ' modifier is misplaced in ORDER BY clause');
                    }

                    if (tok.ttype == SOQLLexer.KW_LAST) {
                        activeSort.nullsLast = true;
                    } else if (tok.ttype == SOQLLexer.KW_FIRST) {
                        activeSort.nullsFirst = true;
                    }

                    if (activeSort.nullsLast && activeSort.nullsFirst) {
                        parseErr(tok, nullsTok.lexeme + ' ' + tok.lexeme + ' clashes with prior NULLS ' + 
                            (tok.ttype == SOQLLexer.KW_LAST ? 'FIRST' : 'LAST'));
                    }

                } else if (state == 1 && (peek == SOQLLexer.KW_ASC || peek == SOQLLexer.KW_DESC)) {
                    tok = toks[lex.next++]; // consume ASC / DESC
                    if (activeSort == null) {
                        parseErr(tok, 'Lead ' + tok.lexeme + ' modifier is misplaced in ORDER BY clause');
                    }
                    
                    if (peek == SOQLLexer.KW_ASC) {
                        activeSort.ascending = true;
                    } else if (peek == SOQLLexer.KW_DESC) {
                        activeSort.descending = true;
                    }

                    if (activeSort.ascending && activeSort.descending) {
                        parseErr(tok, tok.lexeme + ' clashes with prior ' + 
                            (peek == SOQLLexer.KW_ASC ? 'DESC' : 'ASC'));
                    }

                } else if (peek == SOQLLexer.COMMA) {
                    state = 0;
                    // consume and discard the comma, then continue to next sort entity in this list:
                    lex.next++;
                    continue;
                } else if (peek == SOQLLexer.DOT || peek == SOQLLexer.KW_LAST || peek == SOQLLexer.KW_FIRST) {
                    tok = toks[lex.next++];
                    parseErr(tok, (activeSort == null ? 'Lead ' : 'Dangling ') + 
                        tok.lexeme + ' is misplaced in ORDER BY clause');
                } else {
                    // As soon as we hit a token that can't be absorbed into this entity-list, we're done - it's the 
                    // caller's job to determine whether that next token is something it wants to handle or throw an 
                    // error on...
                    break;
                }

            } while (true);
        }

        Boolean isSelectableFunc(Integer ttype) {
            return ttype == SOQLLexer.KW_SAFE || ttype == SOQLLexer.KW_SYSTEM || ttype == SOQLLexer.KW_FIELDSET;
        }

        void addSelectableEntity(SOQLLexer altLexer, SOQLLexer.Token[] refParts, SOQLLexer.Token func, SOQLLexer.Token nestedFunc) {
            SelectElmt sel = new SelectElmt();
            sel.altLexer = altLexer;
            this.selects.add(sel);
            sel.pathToks = refParts;
            if (sel.funcToks != null) {
                sel.funcToks = new SOQLLexer.Token[]{ func };
                sel.funcsCatLC = '.' + func.lexeme.toLowerCase();
                if (nestedFunc != null) {
                    sel.funcToks.add(nestedFunc);
                    sel.funcsCatLC += '.' + nestedFunc.lexeme.toLowerCase();
                }
            }
        }
    }

    private static Object arrayShift(Object[] arr, Integer count) {
        Object elmt;
        while (arr.size() > 0 && count-- > 0) {
            elmt = arr.remove(0);
        }
        return elmt;
    }

    private static Boolean isIdentifierTok(Integer ttype) {
        return ttype == SOQLLexer.NAME || ttype >= SOQLLexer.KEYWORD_MINIMUM;
    }

    private static Boolean isIdentifierTok(SOQLLexer.Token tok) {
        return tok.ttype == SOQLLexer.NAME || tok.ttype >= SOQLLexer.KEYWORD_MINIMUM;
    }

    private static Boolean isIdentifierTok(SOQLLexer.Token tok, String matchLexeme) {
        return (tok.ttype == SOQLLexer.NAME || tok.ttype >= SOQLLexer.KEYWORD_MINIMUM) && tok.lexeme == matchLexeme;
    }

    global SOQLParser() {
        this.refProc = new ReferenceProcessor();
    }
    
    global SOQLParser(Schema.sObjectType baseRefType) {
        this.refProc = new ReferenceProcessor(baseRefType);
    }
    
    global SOQLParser baseRefType(Schema.sObjectType baseRefType) {
/*
        if (baseRefType != null) {
            if (refProc == null || refProc.baseRefType != baseRefType) {
                // TODO: should we carry over partial settings, or nah?
if (refProc == null) {
                this.refProc = new ReferenceProcessor(baseRefType);
} else {
                    // Carry over all prior settings other than baseRefType:
                    this.refProc = new ReferenceProcessor(this);
                    this.refProc.baseRefType = baseRefType;
                }
            }
        } else {
            this.refProc = null;
        }
*/
        if (baseRefType != refProc.baseRefType) {
            this.refProc = new ReferenceProcessor(this.refProc); // carry over prior settings
            this.refProc.baseRefType = baseRefType;
        }
        return this;
    }
    
    global SOQLParser paramBindLoose() {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.paramBindMode = PARAM_BIND_MODE_LOOSE;
        return this;
    }
    
    global SOQLParser paramBindStrict() {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.paramBindMode = PARAM_BIND_MODE_STRICT;
        return this;
    }
    
    global SOQLParser paramBindBlind() {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.paramBindMode = PARAM_BIND_MODE_BLIND;
        return this;
    }

/* mulveling-dev
    @deprecated
    global SOQLParser anchorType(Schema.sObjectType baseRefType) {
        return baseRefType(baseRefType);
    }
*/
    
    global SOQLParser strictRefs(Schema.sObjectType baseRefType) {
        baseRefType(baseRefType);
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.strictRefs = true;
        return this;
    }
    
    global SOQLParser strictRefs(Boolean strictRefs) {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.strictRefs = strictRefs == true;
        return this;
    }
    
    global SOQLParser finesseRefs(Boolean finesseRefs) {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.fixNamespaces = finesseRefs == true;
        refProc.fixLookupSuffixes = finesseRefs == true;
        return this;
    }
    
    global SOQLParser injectParentRefs(String[] injectParentRefs) {
        System.assert(refProc.baseRefType != null, 'Base reference type must first be set');
        refProc.injectParentRefs = injectParentRefs;
        return this;
    }
    
    global SOQLParser refProcessor(ReferenceProcessor refProc) {
        this.refProc = refProc != null ? refProc : new ReferenceProcessor();
        return this;
    }
    
    global ReferenceProcessor refProcessor() {
        return refProc;
    }
    
/* mulveling-dev
    // TODO: deprecate
    global SOQLParser strictTypes(Schema.sObjectType baseRefType) {
        return strictRefs(baseRefType);
    }
    
    // TODO: deprecate
    global SOQLParser strictTypes(Boolean strictRefs) {
        return strictRefs(strictRefs);
    }
    
    global static CondExpr p(String soql) {
        return P.parseCond(soql, true, UNDEFINED_VAL, null);
    }
    
    global static CondExpr p(String soql, Object oneUseGenericBindValues) {
        // note that here we don't shut off the non-spread of bind array elmts; heuristic logic is used on this CondExpr to determine whether to spread or not:
        return P.parseCond(soql, false, oneUseGenericBindValues, null);
    }
    
    global static CondExpr p(String soql, Object bindVal0, Object bindVal1) {
        return P.parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 });
    }
    
    // e.g. parseCond('foo__c=? AND bar__c=? AND baz__c=?', 1, 2, 3); => "foo__c = 1 AND bar__c = 2 AND baz__c = 3"
    global static CondExpr p(String soql, Object bindVal0, Object bindVal1, Object bindVal2) {
        return P.parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 });
    }
    
    global static CondExpr p(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
        return P.parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 });
    }
    
    global static CondExpr p(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
        return P.parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 });
    }
    
    global static CondExpr p(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
        return P.parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 });
    }
    
    global CondExpr parseCond(String soql) {
        return parseCond(soql, true, UNDEFINED_VAL, null);
    }
    
    global CondExpr parseCond(String soql, Object oneUseGenericBindValues) {
        // note that here we don't shut off the non-spread of bind array elmts; heuristic logic is used on this CondExpr to determine whether to spread or not:
        return parseCond(soql, false, oneUseGenericBindValues, null);
    }
    
    global CondExpr parseCond(String soql, Object bindVal0, Object bindVal1) {
        return parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 });
    }
    
    // e.g. parseCond('foo__c=? AND bar__c=? AND baz__c=?', 1, 2, 3); => "foo__c = 1 AND bar__c = 2 AND baz__c = 3"
    global CondExpr parseCond(String soql, Object bindVal0, Object bindVal1, Object bindVal2) {
        return parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 });
    }
    
    global CondExpr parseCond(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
        return parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 });
    }
    
    global CondExpr parseCond(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
        return parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 });
    }
    
    global CondExpr parseCond(String soql, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
        return parseCond(soql, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 });
    }
    
    // this is the generic target method called by all of the overloaded methods
    global CondExpr parseCond(String soql, Boolean alwaysSpreadBindArrayElmts, Object genericBinds, Object[] indexedBinds) {
        CondExpr cond = parseCondExpr(this, soql, 0).alwaysSpreadBindArrayElmts(alwaysSpreadBindArrayElmts);
        if (genericBinds !== UNDEFINED_VAL) {
            cond.bind(genericBinds);
        }
        if (indexedBinds != null) {
            cond.bindIndexed(indexedBinds);
        }
        // we must perform a bind operation, even if empty, to ensure that we don't let unbound anonymous params slip by:
        if (genericBinds === UNDEFINED_VAL && indexedBinds == null) {
            cond.bindNamed(new Map<String, Object>());
        }
        // check whether any anonymous parameters remain unbound; this is a parse error:
        if (cond.lastUnboundAnonParams != null && cond.lastUnboundAnonParams.size() > 0) {
            parseErr(cond.lastUnboundAnonParams[0], 'Anonymous \'?\' parameters must be bound to a value at time of parse');
        }
        // if we have any flags set which require the reference processor, then run that:
        if (refProc.baseRefType != null && refProc.strictRefs == true) {
            cond.traverse(refProc);
        }
        return cond;
    }
    */

    // Base type for all expression elements -- this is the only common ancestor between ExprPart and Value:
    global virtual class Elmt {
        public transient String ser; // for use only be Serializer
        public transient CondExpr serTranslation; // for use only be Serializer
        public virtual void traverse(Visitor v) {}
    }
    
    // Base type for all expresson parts which may show up in the parser's unfinished-parts stack:
    global virtual class ExprPart extends Elmt {
        // The following variables are only needed/used during parsing, when the part is on the parser's stack:
        private transient Integer lvl; // the current expression level of this part
        private transient Integer maxLvl; // the maximum expression level this part can be raised to
        private transient Integer mergeType;
    }
    
    // Base type for all "whole" expressions:
    global virtual class CondExpr extends ExprPart {
        // for use only by the evaluator:
        public transient Boolean eval;
        
        // the goal of these properties is to have a parser instance determinable for every CondExpr, regardless of whether it's:
        //   1. a top parsed condition - in this case paser will be non-null, isTopParsed will be true, and parsedTop / fragmentParent will be null
        //   2. a non-top parsed sub-condition - in this case parsedTop will be set to the top cond and parser is also set; isTopParsed is false and fragmentParent is null
        //   3. a parsed fragment condition - in this case fragmentParent will be non-null; parsedTop and parser will also be set (note: a fragmentParent may point to another fragment since they can be nested)
        //   4. an AndExpr, OrExpr, or NotExpr instantiated directly from an andx, orx, notx method call; parser will be set and all other props are null
        SOQLParser parser;
        CondExpr parsedTop;
        CondExpr fragmentParent;
        Boolean isTopParsed = false;
        
        // for use only be Serializer; some CondExpr instances may have a serialization result (e.g. serTranslation) which is at a different lvl than
        // their parsed lvl. when this value is null the parsed lvl is used by default:
        transient Integer serLvlOverride;
        public Integer serLvl {get{ return serLvlOverride != null ? serLvlOverride : lvl; }}
        
        // for the last bind* method called on this node, this holds any anonymous param tokens that remain unbound after the traversal:
        transient SOQLLexer.Token[] lastUnboundAnonParams;
        
        // the following properties are only compiled (by the parseCond method) for a top-level CondExpr; they are used to determine whether a generic
        // values bind call (i.e. bind(Object) as opposed to the more type-specific calls bindNamed(map) and bindIndexed(array))
        // should treat an array argument as a single value (i.e. bind the full array to a '?' param) or as a list of indexed values (i.e. bind array
        // element #1 to :0, element #2 to :1, etc):
        Integer anonParamCount = 0; // e.g. the expr "foo__c > ? AND bar__c < ?" would result in anonParamCount==2
        Boolean hasIndexedParam = false; // e.g. the expr "foo__c = :0" would result in hasIndexedParam==true
        Boolean alwaysSpreadBindArrayElmts = false;
        global CondExpr alwaysSpreadBindArrayElmts(Boolean flagVal) {
            this.alwaysSpreadBindArrayElmts = flagVal;
            return this;
        }
        
        global SOQLParser getParser() {
            if (parser != null) {
                return parser;
            } else if (parsedTop != null && parsedTop.parser != null) {
                return parsedTop.parser;
            }
            return SOQLParser.P;
        }
        
        Boolean spreadBindArrayElmts {get{
            return alwaysSpreadBindArrayElmts || anonParamCount != 1 || hasIndexedParam;
        }}
        
        global virtual CondExpr empty() {
            return this;
        }
        
        global virtual Boolean isEmpty() {
            return false;
        }
        
/* mulveling-dev
        // Invokes the reference processor with all default settings; normalizes all references (namespace, etc) and validates them
        global CondExpr processRefs(Schema.sObjectType anchorType, Boolean clobberPrior) {
            traverse(new ReferenceProcessor(anchorType).clobberPrior(clobberPrior));
            return this;
        }
*/

        // This method allows the use of reference processor with something other than the default settings (e.g. inject extra parent references)
        global CondExpr processRefs(ReferenceProcessor proc) {
            this.traverse(proc);
            return this;
        }
        
/* mulveling-dev
        // Note that this method may return a different CondExpr instance than 'this'
        // Throws ParseException if rhsString is not valid syntax
        global CondExpr andx(String rhsString) {
            return andx(getParser().parseCond(rhsString, false, UNDEFINED_VAL));
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        // Throws ParseException if rhsString is not valid syntax
        global CondExpr andx(String rhsString, Object rhsBindValues) {
            // note that here we don't shut off the non-spread of bind array elmts; heuristic logic is used on this CondExpr to determine whether to spread or not:
            return andx(getParser().parseCond(rhsString, false, rhsBindValues, null));
        }
        
        global CondExpr andx(String rhsString, Object bindVal0, Object bindVal1) {
            return andx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 }));
        }
        
        global CondExpr andx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2) {
            return andx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 }));
        }
        
        global CondExpr andx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
            return andx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 }));
        }
        
        global CondExpr andx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
            return andx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 }));
        }
        
        global CondExpr andx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
            return andx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 }));
        }
        
        global CondExpr andx(CondExpr rhs) {
            return andx(rhs, UNDEFINED_VAL);
        }
        
        global CondExpr andNot(String rhsString) {
            return andNot(getParser().parseCond(rhsString, false, UNDEFINED_VAL));
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        // Throws ParseException if rhsString is not valid syntax
        global CondExpr andNot(String rhsString, Object rhsBindValues) {
            // note that here we don't shut off the non-spread of bind array elmts; heuristic logic is used on this CondExpr to determine whether to spread or not:
            return andNot(getParser().parseCond(rhsString, false, rhsBindValues, null));
        }
        
        global CondExpr andNot(String rhsString, Object bindVal0, Object bindVal1) {
            return andNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 }));
        }
        
        global CondExpr andNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2) {
            return andNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 }));
        }
        
        global CondExpr andNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
            return andNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 }));
        }
        
        global CondExpr andNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
            return andNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 }));
        }
        
        global CondExpr andNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
            return andNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 }));
        }
        
        global CondExpr andNot(CondExpr rhs) {
            return andx(rhs != null ? rhs.notx() : null, UNDEFINED_VAL);
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        global CondExpr andx(CondExpr rhs, Object rhsBindValues) {
            if (rhs == null || rhs.isEmpty()) {
                return this;
            }
            if (rhsBindValues !== UNDEFINED_VAL) {
                rhs.bind(rhsBindValues);
            }
            if (isEmpty()) {
                return rhs;
            } else if (this.lvl == LVL_AND) {
                ((AndExpr) this).children.add(rhs);
                return this;
            } else {
                AndExpr topExpr = AndExprProto.clone();
                topExpr.parser = getParser();
                topExpr.children = new CondExpr[]{ this, rhs };
                    return topExpr;
            }
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        // Throws ParseException if rhsString is not valid syntax
        global CondExpr orx(String rhsString) {
            return orx(getParser().parseCond(rhsString, false, UNDEFINED_VAL));
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        // Throws ParseException if rhsString is not valid syntax
        global CondExpr orx(String rhsString, Object rhsBindValues) {
            // note that here we don't shut off the non-spread of bind array elmts; heuristic logic is used on this CondExpr to determine whether to spread or not:
            return orx(getParser().parseCond(rhsString, false, rhsBindValues, null));
        }
        
        global CondExpr orx(String rhsString, Object bindVal0, Object bindVal1) {
            return orx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 }));
        }
        
        global CondExpr orx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2) {
            return orx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 }));
        }
        
        global CondExpr orx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
            return orx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 }));
        }
        
        global CondExpr orx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
            return orx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 }));
        }
        
        global CondExpr orx(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
            return orx(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 }));
        }
        
        global CondExpr orx(CondExpr rhs) {
            return orx(rhs, UNDEFINED_VAL);
        }
        
        global CondExpr orNot(String rhsString) {
            return orNot(getParser().parseCond(rhsString, false, UNDEFINED_VAL));
        }
        
        global CondExpr orNot(String rhsString, Object rhsBindValues) {
            return orNot(getParser().parseCond(rhsString, false, rhsBindValues, null));
        }
        
        global CondExpr orNot(String rhsString, Object bindVal0, Object bindVal1) {
            return orNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1 }));
        }
        
        global CondExpr orNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2) {
            return orNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2 }));
        }
        
        global CondExpr orNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3) {
            return orNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3 }));
        }
        
        global CondExpr orNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4) {
            return orNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4 }));
        }
        
        global CondExpr orNot(String rhsString, Object bindVal0, Object bindVal1, Object bindVal2, Object bindVal3, Object bindVal4, Object bindVal5) {
            return orNot(getParser().parseCond(rhsString, true, UNDEFINED_VAL, new Object[]{ bindVal0, bindVal1, bindVal2, bindVal3, bindVal4, bindVal5 }));
        }
        
        global CondExpr orNot(CondExpr rhs) {
            return orx(rhs != null ? rhs.notx() : null, UNDEFINED_VAL);
        }
        
        // Note that this method may return a different CondExpr instance than 'this'
        global CondExpr orx(CondExpr rhs, Object rhsBindValues) {
            if (rhs == null || rhs.isEmpty()) {
                return this;
            }
            if (rhsBindValues !== UNDEFINED_VAL) {
                rhs.bind(rhsBindValues);
            }
            if (isEmpty()) {
                return rhs;
            } else if (this.lvl == LVL_OR) {
                ((OrExpr) this).children.add(rhs);
                return this;
            } else {
                OrExpr topExpr = OrExprProto.clone();
                topExpr.parser = getParser();
                topExpr.children = new CondExpr[]{ this, rhs };
                    return topExpr;
            }
        }
        
        global CondExpr notx() {
            NotExpr notExpr = NotExprProto.clone();
            notExpr.operand = this;
            notExpr.parser = getParser();
            return notExpr;
        }
        
        // !! Note the potential ambiguity posed when paramBindValues is instanceof Object[] -- should the whole array value be assigned to the first
        // indexed/anon param, or should the array elements be spread among all indexed/anon params?
        global CondExpr bind(Object paramBindValues) {
            // If the paramBindValues is an array, then it could have 2 meanings:
            //   1. Map each array element to the indexed/anon parameters
            //   2. Map the entire array value to the first indexed/anon parameter
            // To resolve this ambiguity, we look at special metadata properties set for this CondExp during its parse. If this was CondExpr was a top-level
            // expression, then it will have set anonParamCount<int> and hasIndexedParam<bool>. If it has exactly 1 anon param and no indexed params, then we
            // will treat this as scenario #2 above.
            Boolean isArrayArg = paramBindValues instanceof Object[];
            if (isArrayArg && !this.spreadBindArrayElmts) {
                // once we've bound an array of elements as a single Value, we force the spread of all subsequent array binds:
                this.alwaysSpreadBindArrayElmts = true;
                return bindIndexed(new Object[]{ paramBindValues });
            } else {
                ValueResolver valRez;
                if (isArrayArg) {
                    this.alwaysSpreadBindArrayElmts = true;
                    traverse(valRez = new ValueResolver((Object[]) paramBindValues)
                             .refProc(parser.refProc)
                             .clobberPrior(false));
                } else {
                    traverse(valRez = new ValueResolver(paramBindValues)
                             .refProc(parser.refProc)
                             .clobberPrior(false)
                             .normalizeNamedParams());
                }
                lastUnboundAnonParams = valRez.unboundAnonParams;
                return this;
            }
        }
        
        global CondExpr bindNamed(Map<String, Object> paramBindMap) {
            ValueResolver valRez = new ValueResolver(paramBindMap)
                .refProc(parser.refProc)
                .clobberPrior(false)
                .normalizeNamedParams();
            traverse(valRez);
            lastUnboundAnonParams = valRez.unboundAnonParams;
            return this;
        }
        
        global CondExpr bindIndexed(Object[] paramBindArray) {
            ValueResolver valRez = new ValueResolver(paramBindArray)
                .refProc(parser.refProc)
                .clobberPrior(false);
            traverse(valRez);
            lastUnboundAnonParams = valRez.unboundAnonParams;
            return this;
        }
        
        public CondExpr bindValues(ValueResolver valRez) {
            // note that here, unlike above, we don't transfer parser settings to the given valRez's reference processing settings:
            traverse(valRez.normalizeNamedParams());
            lastUnboundAnonParams = valRez.unboundAnonParams;
            return this;
        }
        */
        
        global String ser() {
            SOQLParser percival = getParser();
            traverse(new Serializer(percival.refProc));
            return ser;
        }
        
        global virtual String ser(ReferenceProcessor justInTimeRefProc) {
            traverse(new Serializer(justInTimeRefProc));
            return ser;
        }
        
        global virtual CondExpr resolveRefs(ReferenceProcessor refProc) {
            traverse(refProc);
            return this;
        }
        
        global virtual CondExpr resolveRefs() {
            System.assert(parser.refProc.baseRefType != null, 'Base reference type must first be set');
            traverse(parser.refProc);
            return this;
        }
        
        global virtual String[] getRawRefs() {
            ReferenceScanner scanner = new ReferenceScanner().rawRefs(true);
            traverse(scanner);
            return scanner.stack[0];
        }
        
        global virtual String[] getResolvedRefs() {
            ReferenceScanner scanner = new ReferenceScanner().rawRefs(false);
            traverse(scanner);
            return scanner.stack[0];
        }
        
        /* Migrated these methods into class SOQLEvaluator:
        global virtual Boolean eval(sObject targetRecord) {
            traverse(new SOQLEvaluator(parser.refProc, targetRecord));
            return eval;
        }
        
        public String[] evalDebug(sObject targetRecord) {
            traverse(new SOQLEvaluator(parser.refProc, targetRecord));
            EvalDebug debug = new EvalDebug();
            traverse(debug);
            return debug.printResults();
        }
        
        public void evalMatchSubResults(sObject targetRecord, Boolean[] expectedSubResults) {
            traverse(new SOQLEvaluator(parser.refProc, targetRecord));
            EvalDebug debug = new EvalDebug();
            traverse(debug);
            System.assert(expectedSubResults != null && expectedSubResults.size() > 0, 'Expected sub-condition results cannot be null or empty');
            System.assert(expectedSubResults.size() == debug.results.size(), 
                          'Expected number of sub-conditions ' + expectedSubResults + ' does not match actual number of sub-conditions ' + debug.results.size());
            for (Integer i=0; i < expectedSubResults.size(); i++) {
                if (expectedSubResults[i] != debug.results[i]) {
                    System.assert(false, 'Sub-condition #' + (i + 1) + ' did not match expected result ' + 
                                  expectedSubResults[i] + '; sub-condition: [' + debug.parts[i].ser() + '] => ' + debug.results[i]);
                }
            }
        }
        */
                
        global String whereClause() {
            return isEmpty() ? '' : ' WHERE ' + ser();
        }
        
        public virtual void traverse(AbstractVisitor v) {
            System.assert(false, 'traverse(AbstractVisitor) must be implemented for all concrete CondExpr subclasses');
        }
    }
    
    // Base type for infix binary-operator expressions that consist of 2 or more child expression terms:
    global virtual class NestExpr extends CondExpr {
        public CondExpr[] children;
        
        global override CondExpr empty() {
            if (children != null) {
                children.clear();
            }
            return this;
        }
        
        global override Boolean isEmpty() {
            if (children == null || children.size() == 0) {
                return true;
            }
            for (CondExpr c : children) {
                if (!c.isEmpty()) {
                    return false;
                }
            }
            return true;
        }
        
        public virtual override void traverse(AbstractVisitor v) {
            if (v.visit(this) == true) {
                for (CondExpr cond : children) {
                    cond.traverse(v);
                }
                v.afterVisit(this);
            }
        }
    }
    
    global class OrExpr extends NestExpr {
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                Integer len = children.size();
                for (Integer i=0; i < len; i++) {
                    CondExpr c = children[i];
                    c.traverse(v);
                }
                v.afterVisit(this);
            }
        }
    }
    
    global class AndExpr extends NestExpr {
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                Integer len = children.size();
                for (Integer i=0; i < len; i++) {
                    CondExpr c = children[i];
                    c.traverse(v);
                }
                v.afterVisit(this);
            }
        }
    }
    
    global class NotExpr extends CondExpr {
        public CondExpr operand;
        
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                if (operand != null) {
                    operand.traverse(v);
                }
                v.afterVisit(this);
            }
        }
        
        public virtual override void traverse(AbstractVisitor v) {
            if (v.visit((CondExpr) this) == true) {
                if (operand != null) {
                    operand.traverse(v);
                }
                v.afterVisit((CondExpr) this);
            }
        }
        
        global override CondExpr empty() {
            operand = null;
            return this;
        }
        
        global override Boolean isEmpty() {
            return operand == null || operand.isEmpty();
        }
    }
    
    // A SimpleExpression may be either a nested expression or a relational/equality expression:
    global class SimpleExpr extends CondExpr {
        public RefExpr ref;
        // Lexer token type of the relational/equality op applied to the ref (lhs) and value (rhs) (e.g. LESS_THAN); note that if
        // relOp == KW_NOT then that actually means the NOT IN operator rather than logical NOT:
        public SOQLLexer.Token relOp;
        // This otherwise redundant property is an accommodation for the NOT IN operator; use this instead of relOp.lexeme:
        public String relOpLexeme;
        // The following only applies to the "between" operator:
        public Boolean[] valPairInclusiveFlags;
        public Value val;
        
        // If nested is not null, then the above vars must be null, and vice-versa:
        public CondExpr nested;
        public SOQLLexer.Token nestedStart; // the left parenthesis token
        
        // Used only by serializer; simple exprs with the beginsWith/endsWith/contains/between op will generate translations during serilization;
        // fo the translations the original simple expr is recorded here to aid in generating better TypeExceptions:
        transient SimpleExpr translatee;
        
        public SOQLLexer.Token originalRelOp {get{
            return translatee != null ? translatee.relOp : relOp;
        }}
        
        public String originalRelOpLexeme {get{
            return translatee != null ? translatee.relOpLexeme : relOpLexeme;
        }}
        
        public Boolean isNotInOp {get{
            return relOp.ttype == SOQLLexer.KW_NOT;
        }}
        
        public Boolean isSetOp {get{
            if (relOp == null) {
                return false;
            }
            Integer ttype = relOp.ttype;
            // note that in this context NOT actually means the NOT IN operator:
            if (ttype == SOQLLexer.KW_IN || ttype == SOQLLexer.KW_NOT || ttype == SOQLLexer.KW_INCLUDES || ttype == SOQLLexer.KW_EXCLUDES) {
                return true;
            }
            return false;
        }}
        
        global override CondExpr empty() {
            this.nested = null;
            this.ref = null;
            this.relOp = null;
            this.relOpLexeme = null;
            this.val = null;
            return this;
        }
        
        global override Boolean isEmpty() {
            if (nested != null) {
                return nested.isEmpty();
            } else {
                // TODO: expand this logic when we support SimpleExpr params:
                return ref == null && relOp == null && val == null;
            }
        }
        
        // strips redundant nestings (if any; if none simply returns this) and returns the final relevant cond expr:
        public CondExpr unwrap() {
            CondExpr unwrapped = this;
            while (unwrapped != null && unwrapped.lvl == LVL_SIMPLE && ((SimpleExpr) unwrapped).nested != null) {
                unwrapped = ((SimpleExpr) unwrapped).nested;
            }
            return unwrapped;
        }
        
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                if (nested != null) {
                    nested.traverse(v);
                } else {
                    ref.traverse(v);
                    val.traverse(v);
                }
                v.afterVisit(this);
            }
        }
        
        public virtual override void traverse(AbstractVisitor v) {
            if (v.visit((CondExpr) this) == true) {
                if (nested != null) {
                    nested.traverse(v);
                } else {
                    ref.traverse(v);
                    if (v.traverseValues == true) {
                        val.traverse(v);
                    }
                }
                v.afterVisit((CondExpr) this);
            }
        }
    }
    
    global virtual class RefExpr extends ExprPart {
        public SOQLLexer.Token[] names;
        
        // the following properties are set by ReferenceProcessor:
        
        // records the last ReferenceProcessor instance to have processed this expression part:
        public ReferenceProcessor refProc;
        public RefDesc refHead;
        public RefDesc refTail;
        // TODO: replace the following with refHead, refTail:
        
        // !! Had to kill this DescribeFieldResult declaration in favor of sObjectField, because the former is NOT 
        // serializable via Queueables and Batchables:
        //public transient Schema.DescribeFieldResult fieldType;
        public Schema.sObjectField fieldTypeToken;
        public Schema.DisplayType fieldDisplayType;
        public Schema.SOAPType fieldSoapType;
        
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                v.afterVisit(this);
            }
        }
        
        public virtual void traverse(AbstractVisitor v) {
            if (v.visit(this) == true) {
                v.afterVisit(this);
            }
        }
        
        public String getFullResolvedDescripString() {
            if (refTail != null) {
                return refTail.getResolvedDescripString();
            } else {
                return toString();
            }
        }
        
        public override String toString() {
            String[] parts = new String[]{};
            for (SOQLLexer.Token tok : names) {
                parts.add(tok.lexeme);
            }
            return String.join(parts, '.');
        }
    }
    
    global class ValueList extends Value {
        public ValueElmt[] elements;
        
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                Integer len = elements.size();
                for (Integer i=0; i < len; i++) {
                    ValueElmt elmt = elements[i];
                    elmt.traverse(v);
                }
                v.afterVisit(this);
            }
        }
        
        public override void traverse(AbstractVisitor v) {
            if (v.visit((Value) this) == true) {
                for (Value val : elements) {
                    val.traverse(v);
                }
                v.afterVisit((Value) this);
            }
        }
        
        // TODO: cache eval results
        // note that isLikeOpTarget is not used in the list impl, since a list cannot be the target of a LIKE op:
        public override Object eval(Boolean isLikeOpTarget, Object heent) {
            if (evald == true) {
                return eval;
            }
            Object[] arr = new Object[]{};
                for (ValueElmt elmt : elements) {
                    arr.add(elmt.eval(isLikeOpTarget, heent));
                }
            this.evald = true;
            return this.eval = arr;
        }
    }
    
    global class ValueElmt extends Value {
        // The lead token for a value element is always recorded here by the parser -- note that this can be used to e.g. get the actual lexeme from a number literal:
        public SOQLLexer.Token loc;
        
        // All of the following variables are mutually exclusive; exactly 1 must be non-null, and no 2 can be non-null:
        
        public Boolean isString;
        // if this is a string value elmt, then either stringLitParts OR stringBindValue must be non-null (and they are mutually
        // exclusive). if stringLitParts is not null, then it must have size > 0 and stringLitCodes must match this size:
        public String[] stringLitParts;
        public Integer[] stringLitCodes;
        public String stringBindValue;
        // the resolved string value:
        public String resolvedStringValue;
        // the resolved string serialization, with wrapping single-quotes and backslash escapes:
        public String resolvedStringSer;
        
        public Decimal numberLit;
        // this holds Infinity, -Infinity, and NaN since they cannot be represented by a Decimal:
        public Double specialNumberLit; 
        // Lexer token type of KW_NULL, KW_FALSE, or KW_TRUE:
        public SOQLLexer.Token kwLit;
        public Date dateLit;
        public DateTime dateTimeLit;
        // date formula token type (e.g. KW_NEXT_YEAR); some date forumlas (e.g. KW_NEXT_N_YEARS) may be coupled with an :N integer value:
        public SOQLLexer.Token dateFormula;
        public Integer dateFormula_N;
        
        // Colon or '?' syntax -- for referencing an external variable value -- will be recorded in the following properties:
        
        // if one of the following 3 mutually-exclusive properties is non-null, then its token value will be copied here:
        public SOQLLexer.Token param;
        // the following 3 properties are mutually exclusive; a maximum of 1 may be non-null:
        public SOQLLexer.Token paramName; // named param, e.g. ":foo"
        public SOQLLexer.Token paramIndex; // indexed param, e.g. ":0"
        public Integer paramIndexIntVal;
        public SOQLLexer.Token paramAnon; // anonymous positioned param "?"
        
        // After binding a value to a param, its resolved ValueElmt or ValueList gets stored here:
        public Value paramResolvedValue;

        // New feture allowing array-value bindings to be remapped to predetermined local scope variables (e.g. Id[] id1, id2, id3), 
        // for performance and scalability reasons:
        public LocalReBind localReBind;
        
        public virtual override void traverse(Visitor v) {
            if (v.visit(this) == true) {
                // a resolved value (from either a named, indexed, or anonymous value parameter) may be either a ValueElmt or a ValueList; in either case traverse it:
                if (paramResolvedValue != null) {
                    paramResolvedValue.traverse(v);
                }
                v.afterVisit(this);
            }
        }
        
        public override void traverse(AbstractVisitor v) {
            if (v.visit((Value) this) == true) {
                // a resolved value (from either a named, indexed, or anonymous value parameter) may be either a ValueElmt or a ValueList; in either case traverse it:
                if (paramResolvedValue != null) {
                    paramResolvedValue.traverse(v);
                }
                v.afterVisit((Value) this);
            }
        }
        
        // the value of the "isLikeOpTarget" flag should not change for multiple calls on any given instance, so it's safe to cache the 
        // resolved sers:
        public String getStringSer(Boolean isLikeOpTarget) {
            if (resolvedStringSer != null) {
                return resolvedStringSer;
            } else if (stringBindValue != null) {
                this.resolvedStringSer = stringBindValue;
                // check for backslashes and/or single-quotes, which must be backslashed for serialization:
                if (resolvedStringSer.containsAny('\\\'')) {
                    if (isLikeOpTarget == true) {
                        // if this string value is to be the rhs of a SOQL like expr, then double-up backslashes that are NOT followed by
                        // a % or _, and then backslash all single-quotes:
                        this.resolvedStringSer = resolvedStringSer.replaceAll('\\\\(?!%|_)', '\\\\\\\\').replace('\'', '\\\'');
                    } else {
                        // unconditionally double-up all backslashes and then backslash all single-quotes:
                        this.resolvedStringSer = resolvedStringSer.replace('\\', '\\\\').replace('\'', '\\\'');
                    }
                }
                // replace all \r\n, \n, and \r with literal "\r\n\", "\n", and "\r" respectively:
                if (resolvedStringSer.containsAny('\n\r')) {
                    this.resolvedStringSer = resolvedStringSer.replace('\r\n', '\\r\\n').replace('\n', '\\n').replace('\r', '\\r');
                }
                //return '\'' + resolvedStringSer + '\'';
                return this.resolvedStringSer = '\'' + resolvedStringSer + '\'';
            } else if (stringLitParts != null) {
                String[] resParts = new String[]{ '\'' };
                for (Integer i=0; i < stringLitParts.size(); i++) {
                    Integer code = stringLitCodes[i];
                    if (code == 0) {
                        resParts.add(stringLitParts[i]);
                    } else if (code == 1 || isLikeOpTarget == true) {
                        resParts.add('\\');
                        resParts.add(stringLitParts[i]);
                        // else code is 2 and we're not the target of a like clause; \% and \_ sequences reduce to % and _ respectively:
                    } else {
                        resParts.add(stringLitParts[i]);
                    }
                }
                resParts.add('\'');
                return this.resolvedStringSer = String.join(resParts, '');
            }
            return null;
        }
        
        // When isLikeOpTarget == true, then the resolved value is actually compiled as a regexp/pattern string. Note that the value
        // of the "isLikeOpTarget" flag will never change amongst multiple calls on any given instance, so it's safe to cache the 
        // resolved values for immediate return on subsequent calls.
        public String getStringValue(Boolean isLikeOpTarget) {
            if (resolvedStringValue != null) {
                // immediate return of cached value:
                return resolvedStringValue;
            } else if (stringBindValue != null) {
                // like-op target, so build a regexp string from the literal bind value string:
                if (isLikeOpTarget == true) {
                    String[] rhsChars = stringBindValue.split('');
                    String[] regexpParts = new String[]{};
                        Integer backslashRunCount = 0;
                    for (String ch : rhsChars) {
                        if (ch.isAlphanumeric()) {
                            regexpParts.add(ch);
                        } else if (ch == '\\') {
                            regexpParts.add('\\\\');
                            backslashRunCount++;
                            continue;
                        } else if (ch == '%' && Math.mod(backslashRunCount, 2) == 0) {
                            regexpParts.add('(?:.|[\\r\\n])*');
                        } else if (ch == '_' && Math.mod(backslashRunCount, 2) == 0) {
                            regexpParts.add('(?:.|[\\r\\n])');
                        } else if (ch == '\n') {
                            regexpParts.add('\\n');
                        } else if (ch == '\r') {
                            regexpParts.add('\\r');
                        } else {
                            regexpParts.add('\\' + ch);
                        }
                        backslashRunCount = 0;
                    }
                    return this.resolvedStringValue = String.join(regexpParts, '');
                    // not a like-op target, so just return the bind value string as-is:
                } else {
                    return this.resolvedStringValue = stringBindValue;
                }
            } else if (stringLitParts != null) {
                // like-op target, so build a regexp string:
                if (isLikeOpTarget == true) {
                    String[] regexpParts = new String[]{};
                    for (Integer i=0; i < stringLitParts.size(); i++) {
                        String part = stringLitParts[i];
                        Integer code = stringLitCodes[i];
                        if (code == 0 && part.length() > 0) {
                            String[] partChars = part.split('');
                            for (String ch : partChars) {
                                if (ch.isAlphanumeric()) {
                                    regexpParts.add(ch);
                                } else if (ch == '\\') {
                                    regexpParts.add('\\\\');
                                } else if (ch == '%') {
                                    regexpParts.add('(?:.|[\\r\\n])*');
                                } else if (ch == '_') {
                                    regexpParts.add('(?:.|[\\r\\n])');
                                } else if (ch == '\n') {
                                    regexpParts.add('\\n');
                                } else if (ch == '\r') {
                                    regexpParts.add('\\r');
                                } else {
                                    regexpParts.add('\\' + ch);
                                }
                            }
                            // we backslash-escape all code==1 and code==2 parts (note that \r and \n become literal "\r" and
                            // "\n" 2-char sequences, which is desired in this case):
                        } else {
                            regexpParts.add('\\' + part);
                        }
                    }
                    return this.resolvedStringValue = String.join(regexpParts, '');
                    // not a like-op target, so build a literal string:
                } else {
                    String[] resParts = new String[]{};
                    for (Integer i=0; i < stringLitParts.size(); i++) {
                        Integer code = stringLitCodes[i];
                        if (code == 0) {
                            resParts.add(stringLitParts[i]);
                        } else if (code == 1) {
                            String ch = stringLitParts[i];
                            if (ch.containsAny('nr')) {
                                if (ch == 'n') {
                                    resParts.add('\n');
                                } else {
                                    resParts.add('\r');
                                }
                            } else {
                                resParts.add(ch);
                            }
                            // else code == 2 means we have a \% or \_ sequence that must be reduced to % and _ because this is not 
                            // a LIKE op target:
                        } else {
                            resParts.add(stringLitParts[i]);
                        }
                    }
                    return this.resolvedStringValue = String.join(resParts, '');
                }
            }
            return null;
        }
        
        // "hint" is a freaking reserved word in Apex, so "heent":
        public override Object eval(Boolean isLikeOpTarget, Object heent) {
            if (evald == true) {
                return eval;
            }
            Object val;
            if (param != null) {
                if (paramResolvedValue != null) {
                    val = paramResolvedValue.eval(isLikeOpTarget, heent);
                } else {
                    evalErr(loc, 'Parameter :' + param.lexeme + ' has not been bound to a value');
                }
            } else if (isString == true) {
                val = resolvedStringValue != null ? resolvedStringValue : getStringValue(isLikeOpTarget);
                // else this is a non-recursive and non-string value:
            } else {
                if (numberLit != null) {
                    val = numberLit;
                } else if (specialNumberLit != null) {
                    val = specialNumberLit;
                } else if (kwLit != null) {
                    if (kwLit.ttype == SOQLLexer.KW_TRUE) {
                        val = true;
                    } else if (kwLit.ttype == SOQLLexer.KW_FALSE) {
                        val = false;
                    }
                    // KW_NULL: null is the default for val, so we don't need to explicitly detect KW_NULL...
                } else if (dateLit != null) {
                    val = dateLit;
                } else if (dateTimeLit != null) {
                    val = dateTimeLit;
                    // date formulas are icky.
                    // date formulas resolve val to either a DateTime[2] array (if hint="datetime") or a Date[2] array:
                } else if (dateFormula != null) {
                    Boolean datetimeTarget = heent == 'DateTime';
                    Integer ttype = dateFormula.ttype;
                    // Range codes array =>
                    // [<start offset>, <start units>, <range offset>, <range units>]:
                    // range offset should always be nonzero
                    Integer[] codes;
                    if (ttype == SOQLLexer.KW_TODAY) {
                        codes = new Integer[]{ 0, null, 0, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_TOMORROW) {
                        codes = new Integer[]{ 1, UNIT_DAY, 0, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_YESTERDAY) {
                        codes = new Integer[]{ -1, UNIT_DAY, 0, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_NEXT_90_DAYS) {
                        codes = new Integer[]{ 0, null, 90, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_NEXT_N_DAYS) {
                        codes = new Integer[]{ 0, null, dateFormula_N, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_LAST_90_DAYS) {
                        codes = new Integer[]{ 0, null, -90, UNIT_DAY };
                    } else if (ttype == SOQLLexer.KW_LAST_N_DAYS) {
                        codes = new Integer[]{ 0, null, -dateFormula_N, UNIT_DAY };
                            
                    // TODO:
                    } else {
                        evalErr(loc, (datetimeTarget ? 'DateTime' : 'Date') + ' formula ' + dateFormula.lexeme + 
                                ' not yet supported for dynamic evaluation');
                    }
                    
                    Integer startOffset = codes[0];
                    Integer startUnits = codes[1];
                    Integer rangeOffset = codes[2];
                    Integer rangeUnits = codes[3];
                    if (datetimeTarget) {
                        DateTime start = System.now();
                        if (startOffset != 0) {
                            if (startUnits == UNIT_DAY) { // days
                                start = start.addDays(startOffset);
                                // TODO:
                            } else { System.assert(false, 'Date Range units other than Day have not yet been implemented'); }
                            /*else if (startUnits == UNIT_WEEK) { // weeks
                                start = start.addDays(startOffset * 7);
                            } else if (startUnits == UNIT_MONTH) { // months
                                start = start.addMonths(startOffset);
                            } else if (startUnits == UNIT_QUARTER) {
                                // TODO: quarters
                            } else if (startUnits == UNIT_FISCAL_QTR) {
                                // TODO: fiscal_quarters
                            } else if (startUnits == UNIT_YEAR) { // years
                                start = start.addYears(startOffset);
                            }*/
                        }
                        
                        if (rangeUnits == UNIT_DAY) {
                            val = dayRangeDt(start, rangeOffset);
                            // TODO:
                        } else { System.assert(false, 'Date Range units other than Day have not yet been implemented'); }
                        /*
                            else if (rangeUnits == UNIT_WEEK) {
                            // TODO:
                            val = weekRangeDt(start, rangeOffset);
                        } else if (rangeUnits == UNIT_MONTH) {
                            // TODO:
                            val = monthRangeDt(start, rangeOffset);
                        } else if (rangeUnits == UNIT_QUARTER) {
                            // TODO:
                            //val = quarterRangeDt(start, rangeOffset);
                        } else if (rangeUnits == UNIT_FISCAL_QTR) {
                            // TODO:
                            //val = fiscalQuarterRangeDt(start, rangeOffset);
                        } else if (rangeUnits == UNIT_YEAR) {
                            // TODO:
                            val = yearRangeDt(start, rangeOffset);
                        }*/
                    } else {
                        Date start = System.today();
                        if (startOffset != 0) {
                            if (startUnits == UNIT_DAY) { // days
                                start = start.addDays(startOffset);
                                // TODO:
                            } else { System.assert(false, 'Date Range units other than Day have not yet been implemented'); }
                            /*else if (startUnits == UNIT_WEEK) { // weeks
                                start = start.addDays(startOffset * 7);
                            } else if (startUnits == UNIT_MONTH) { // months
                                start = start.addMonths(startOffset);
                            } else if (startUnits == UNIT_QUARTER) {
                                // TODO: quarters
                            } else if (startUnits == UNIT_FISCAL_QTR) {
                                // TODO: fiscal_quarters
                            } else if (startUnits == UNIT_YEAR) { // years
                                start = start.addYears(startOffset);
                            }
                            */
                        }
                        
                        if (rangeUnits == UNIT_DAY) {
                            val = dayRange(start, rangeOffset);
                            // TODO:
                        } else { System.assert(false, 'Date Range units other than Day have not yet been implemented'); }
                        /*else if (rangeUnits == UNIT_WEEK) {
                            // TODO:
                            //val = weekRange(start, rangeOffset);
                        } else if (rangeUnits == UNIT_MONTH) {
                            // TODO:
                            //val = monthRange(start, rangeOffset);
                        } else if (rangeUnits == UNIT_QUARTER) {
                            // TODO:
                            //val = quarterRange(start, rangeOffset);
                        } else if (rangeUnits == UNIT_FISCAL_QTR) {
                            // TODO:
                            //val = fiscalQuarterRange(start, rangeOffset);
                        } else if (rangeUnits == UNIT_YEAR) {
                            // TODO:
                            //val = yearRange(start, rangeOffset);
                        }
                        */
                    }
                }
                
                if (isLikeOpTarget == true && val != null) {
                    // TODO: should we allow this?
                    evalErr(loc, 'LIKE operator expects a String right-hand side value; got incompatible value [' + val + ']');
                }
            }
            
            this.evald = true;
            return this.eval = val;
        }
    }
    
    static final Integer UNIT_DAY = 0;
    static final Integer UNIT_WEEK = 1;
    static final Integer UNIT_MONTH = 2;
    static final Integer UNIT_QUARTER = 3;
    static final Integer UNIT_FISCAL_QTR = 4;
    static final Integer UNIT_YEAR = 5;
    
    public static final Time Time00 = Time.newInstance(0, 0, 0, 0);
    public static final Time Time24 = Time.newInstance(23, 59, 59, 999);
    
    static DateTime[] dayRangeDt(DateTime anchorDate, Integer rangeOffsetUnits) {
        Date start = anchorDate.date();
        if (rangeOffsetUnits >= 0) {
            return new DateTime[] {
                DateTime.newInstance(start, Time00),
                DateTime.newInstance(start.addDays(rangeOffsetUnits - 1), Time24)
            };
        } else {
            return new DateTime[] {
                DateTime.newInstance(start.addDays(rangeOffsetUnits), Time00),
                DateTime.newInstance(start, Time00)
            };
        }
    }
    
    static Date[] dayRange(Date anchorDate, Integer rangeOffsetUnits) {
        Date start = anchorDate;
        if (rangeOffsetUnits >= 0) {
            return new Date[] {
                anchorDate,
                //anchorDate.addDays(rangeOffsetUnits - 1)
                anchorDate.addDays(rangeOffsetUnits)
            };
        } else {
            return new Date[] {
                anchorDate.addDays(rangeOffsetUnits),
                //anchorDate.addDays(-1)
                anchorDate.addDays(0)
            };
        }
    }
    
    /*
    static DateTime[] weekRangeDt(DateTime anchorDate, Integer rangeOffsetUnits) {
        Date start = anchorDate.date().toStartOfWeek();
        if (rangeOffsetUnits >= 0) {
            return new DateTime[]{
                DateTime.newInstance(start, Time00),
                DateTime.newInstance(start.addDays((rangeOffsetUnits - 1) * 7 + 6), Time24)
            };
        } else {
            return new DateTime[]{
                DateTime.newInstance(start.addDays(7 * rangeOffsetUnits), Time00),
                DateTime.newInstance(start, Time00)
            };
        }
    }

    static DateTime[] monthRangeDt(DateTime anchorDate, Integer rangeOffsetUnits) {
        Date start = anchorDate.date().toStartOfMonth();
        if (rangeOffsetUnits >= 0) {
            return new DateTime[]{
                DateTime.newInstance(start, Time00),
                DateTime.newInstance(start.addMonths(rangeOffsetUnits).addDays(-1), Time24)
            };
        } else {
            return new DateTime[]{
                DateTime.newInstance(start.addMonths(rangeOffsetUnits), Time00),
                DateTime.newInstance(start, Time00)
            };
        }
    }

    // TODO: quarter, fiscal_quarter...

    static DateTime[] yearRangeDt(DateTime anchorDate, Integer rangeOffsetUnits) {
        Date start = Date.newInstance(anchorDate.date().year(), 1, 1);
        if (rangeOffsetUnits >= 0) {
            return new DateTime[]{
                DateTime.newInstance(start, Time00),
                DateTime.newInstance(start.addYears(rangeOffsetUnits).addDays(-1), Time24)
            };
        } else {
            return new DateTime[]{
                DateTime.newInstance(start.addYears(rangeOffsetUnits), Time00),
                DateTime.newInstance(start, Time00)
            };
        }
    }
    */
    
    global virtual class Value extends Elmt {
        // we need both a flag and a value cache, because we may have resolved to a null value:
        public Boolean evald;
        // rhs values cache their resolved values, because they can never change, and resolving them can be CPU-intensive:
        public Object eval;
        // "hint" is a freaking reserved word in apex, hence "heent":
        public virtual Object eval(Boolean isLikeOpTarget, Object heent) { System.assert(false, 'Value.eval not implemented'); return null; }
        public transient String[] serParts; // for use only by Serializer
        
        public virtual void traverse(AbstractVisitor v) {}
    }
    
    global virtual class Visitor {
        /*
        @deprecated
        global Elmt[] parents;
        // returns the closest parent (of the currently traversed element) that is a simple relational/equality expression; returns null if there is no such parent:
        @deprecated
        global SimpleExpr closestRelEqExpr() { System.assert(false, 'Method Visitor.closestRelEqExpr has been removed'); return null; }
        */

        global virtual Boolean visit(OrExpr orExpr) { return true; }
        global virtual void afterVisit(OrExpr orExpr) {}
        global virtual Boolean visit(AndExpr andExpr) { return true; }
        global virtual void afterVisit(AndExpr andExpr) {}
        global virtual Boolean visit(NotExpr notExpr) { return true; }
        global virtual void afterVisit(NotExpr notExpr) {}
        global virtual Boolean visit(SimpleExpr simpleExpr) { return true; }
        global virtual void afterVisit(SimpleExpr simpleExpr) {}
        global virtual Boolean visit(RefExpr refExpr) { return true; }
        global virtual void afterVisit(RefExpr refExpr) {}
        global virtual Boolean visit(ValueList valueList) { return true; }
        global virtual void afterVisit(ValueList valueList) {}
        global virtual Boolean visit(ValueElmt valueElmt) { return true; }
        global virtual void afterVisit(ValueElmt valueElmt) {}
    }
    
    public virtual class AbstractVisitor {
        Boolean traverseValues = false;
        
        public AbstractVisitor traverseValues(Boolean traverse) {
            this.traverseValues = traverse;
            return this;
        }
        
        public virtual Boolean visit(CondExpr cond) { return true; }
        public virtual void afterVisit(CondExpr cond) {}
        public virtual Boolean visit(RefExpr refExpr) { return true; }
        public virtual void afterVisit(RefExpr refExpr) {}
        public virtual Boolean visit(Value val) { return true; }
        public virtual void afterVisit(Value val) {}
    }
    
    // support function for "between" operator
    // throws TypeException if x and y are not compatible types for this operation
    static ValueElmt[] heuristicOrderValuePair(ValueElmt x, ValueElmt y) {
        Boolean rev = false;
        if (x.numberLit != null && y.numberLit != null) {
            rev = x.numberLit > y.numberLit;
        } else if (x.isString == true && y.isString == true) {
            // we know it's not a like-op target because this method is only used for "between" ops:
            final Boolean isLikeOpTarget = false;
            String xVal = x.resolvedStringValue != null ? x.resolvedStringValue : x.getStringValue(isLikeOpTarget);
            String yVal = y.resolvedStringValue != null ? y.resolvedStringValue : y.getStringValue(isLikeOpTarget);
            rev = xVal.toLowerCase() > yVal.toLowerCase();
        } else if (x.dateFormula != null || y.dateFormula != null) {
            // TODO: for now we assume the order is OK as-is, but in the future try to resolve and order at least some date formulas:
            //throw new TypeException('Between operator does not support date forumlas' + loc(x.loc));
            return new ValueElmt[]{ x, y };
                } else if (x.dateLit != null && y.dateLit != null) {
                    rev = x.dateLit > y.dateLit;
                } else if ((x.dateLit != null || x.dateTimeLit != null) &&
                           (y.dateLit != null || y.dateTimeLit != null)) {
                               Time midnight = Time.newInstance(0, 0, 0, 0);
                               DateTime xres, yres;
                               xres = x.dateLit != null ? DateTime.newInstance(x.dateLit, midnight) : x.dateTimeLit;
                               yres = y.dateLit != null ? DateTime.newInstance(y.dateLit, midnight) : y.dateTimeLit;
                               rev = xres.getTime() > yres.getTime();
                           } else if (x.kwLit != null && y.kwLit != null) {
                               typeErr(x.loc, x.kwLit.ttype == SOQLLexer.KW_NULL ? 'Between operator does not support null value arguments'
                                       : 'Between operator does not support boolean value arguments');
                           } else {
                               typeErr(y.loc, 'Between operator requires value-pair arguments to be of matching data types');
                           }
        return rev ? new ValueElmt[]{ y, x } : new ValueElmt[]{ x, y };
            }
    
    static final Integer PARAM_BIND_MODE_BLIND  = 0;
    static final Integer PARAM_BIND_MODE_LOOSE  = 1;
    static final Integer PARAM_BIND_MODE_STRICT = 2;
    
    // Validates all reference chains in a condition and performs optional transformations on them. This process is idempotent:
    global virtual class ReferenceProcessor extends Visitor {
        public Schema.sObjectType baseRefType;
        Boolean strictRefs = false;
        //Boolean validate = true;
        Boolean fixNamespaces = true;
        Boolean fixLookupSuffixes = true;
        // Use this if you need to rewrite your condition to go through additional parent references:
        String[] injectParentRefs;
        
        ReferenceRewriter rewriter;
        Integer paramBindMode = PARAM_BIND_MODE_LOOSE;
        
        global ReferenceProcessor() {}
        
        global ReferenceProcessor(ReferenceProcessor deriveSettings) {
            if (deriveSettings != null) {
                ReferenceProcessor srcProc = deriveSettings;
                this.baseRefType = srcProc.baseRefType;
                this.strictRefs = srcProc.strictRefs == true;
                this.fixNamespaces = srcProc.fixNamespaces == true;
                this.fixLookupSuffixes = srcProc.fixLookupSuffixes == true;
                this.injectParentRefs = srcProc.injectParentRefs;
            }
        }

        global ReferenceProcessor(SOQLParser deriveSettings) {
            this(deriveSettings != null ? deriveSettings.refProc : null);
        }
        
        global ReferenceProcessor(Schema.sObjectType baseRefType) {
            this.baseRefType = baseRefType;
            this.strictRefs = baseRefType != null;
        }
        
        // virtual only because managed packages suck:
        global virtual ReferenceProcessor paramBindLoose() {
            this.paramBindMode = PARAM_BIND_MODE_LOOSE;
            return this;
        }
        
        // virtual only because managed packages suck:
        global virtual ReferenceProcessor paramBindStrict() {
            this.paramBindMode = PARAM_BIND_MODE_STRICT;
            return this;
        }
        
        // virtual only because managed packages suck:
        global virtual ReferenceProcessor paramBindBlind() {
            this.paramBindMode = PARAM_BIND_MODE_BLIND;
            return this;
        }
        
/* mulveling-dev
        @deprecated
        global ReferenceProcessor clobberPrior(Boolean clobberPrior) {
            return this;
        }
*/
        
        global ReferenceProcessor strictRefs(Boolean strictRefs) {
            this.strictRefs = strictRefs == true;
            return this;
        }
        
        global ReferenceProcessor fixNamespaces(Boolean fixNamespaces) {
            this.fixNamespaces = fixNamespaces == true;
            return this;
        }
        
        global ReferenceProcessor fixLookupSuffixes(Boolean fixLookupSuffixes) {
            this.fixLookupSuffixes = fixLookupSuffixes == true;
            return this;
        }
        
        global ReferenceProcessor injectParentRefs(String[] injectParentRefs) {
            this.injectParentRefs = injectParentRefs;
            return this;
        }
        
        public ReferenceProcessor rewriter(ReferenceRewriter rewriter) {
            this.rewriter = rewriter;
            return this;
        }
        
        global virtual override Boolean visit(RefExpr refExpr) {
            refExpr.refProc = this;
            refExpr.refHead = null;
            refExpr.refTail = null;
            //refExpr.fieldType = null;
            refExpr.fieldTypeToken = null;
            refExpr.fieldDisplayType = null;
            refExpr.fieldSoapType = null;
            RefDesc head;
            RefDesc tail;
            RefDesc prev;
            
            if (injectParentRefs != null) {
                SOQLLexer.Token injectPoint = refExpr.names[0];
                for (Integer i=0; i < injectParentRefs.size(); i++) {
                    String injectName = injectParentRefs[i];
                    RefDesc desk = new RefDesc();
                    desk.refExpr = refExpr;
                    desk.baseRefType = baseRefType;
                    desk.prev = prev;
                    if (prev != null) {
                        prev.next = desk;
                    }
                    desk.srcIndex = -1;
                    desk.srcTok = injectPoint;
                    desk.srcName = null; //injectPoint.lexeme;
                    desk.name = injectName;
                    desk.isDynamic = false;
                    if (head == null) {
                        refExpr.refHead = head = desk;
                    }
                    prev = desk;
                }
            }
            Integer i = 0;
            for (SOQLLexer.Token nameTok : refExpr.names) {
                RefDesc desk = new RefDesc();
                desk.refExpr = refExpr;
                desk.baseRefType = baseRefType;
                desk.prev = prev;
                if (prev != null) {
                    prev.next = desk;
                }
                desk.srcIndex = i++;
                desk.srcTok = nameTok;
                desk.srcName = desk.name = nameTok.lexeme;
                desk.isDynamic = false;
                if (head == null) {
                    refExpr.refHead = head = desk;
                }
                prev = desk;
            }
            
            RefDesc node = head;
            if (rewriter != null) {
                rewriter.start(head);
            }
            do {
                if (rewriter != null) {
                    rewriter.rewrite(node);
                }
                if (!node.isDynamic && node.holderSObjType != null) {
                    try {
                        node.resolveSObject();
                    } catch (ReferenceException refErr) {
                        if (strictRefs) {
                            throw refErr;
                        }
                    }
                }
                if (node.next != null) {
                    // dynamic flag always carries forward:
                    node.next.isDynamic = node.isDynamic;
                    node = node.next;
                } else {
                    break;
                }
            } while (true);
            
            refExpr.refTail = node;
            //refExpr.fieldType = node.fieldType;
            refExpr.fieldTypeToken = node.fieldTypeToken;
            refExpr.fieldDisplayType = node.fieldDisplayType;
            refExpr.fieldSoapType = node.fieldSoapType;
            // reference processor never needs to traverse below the RefExpr level:
            return false;
        }
        
        // this vistor has no need to traverse the values, so cancel it:
        global virtual override Boolean visit(ValueList valueList) {
            return false;
        }
    }
    
    public virtual class ReferenceRewriter {
        public virtual void start(RefDesc headRef) {}
        public virtual void rewrite(RefDesc rewriteable) {}
    }
    
    // models a doubly-linked list of reference parts/links in a compound reference expression:
    public class RefDesc {
        RefExpr refExpr {get; private set;}
        
        public Schema.sObjectType baseRefType {get; private set;}
        public RefDesc prev {get; private set;}
        public RefDesc next {get; private set;}
        public Integer srcIndex {get; private set;}
        public SOQLLexer.Token srcTok {get; private set;}
        public String srcName {get; private set;}
        public String name {get; set;}
        public String api {get; set;} // calculated in resolveSObject
        public String normApi {get; set;} // calculated in resolveSObject
        public Boolean isDynamic {get; private set;}
        
        public Schema.sObjectType sobjType {get; private set;}
        // !! Had to kill this DescribeFieldResult declaration in favor of sObjectField, because the former is NOT 
        // serializable via Queueables and Batchables:
        //public Schema.DescribeFieldResult fieldType {get; private set;}
        public Schema.sObjectField fieldTypeToken;
        public Schema.DisplayType fieldDisplayType;
        public Schema.SOAPType fieldSoapType;
        
        public Schema.sObjectType holderSObjType {get{
            if (isDynamic == true) {
                return null;
            } else if (prev != null) {
                return prev.sobjType;
            } else {
                return baseRefType;
            }
        }}
        
        public Boolean isHead {get{ return prev == null; }}
        public Boolean isTail {get{ return next == null; }}
        public Boolean isInterior {get{ return prev != null && next != null; }}
        
        public RefDesc head {get{
            return refExpr.refHead;
        }}
        
        public RefDesc tail {get{
            return refExpr.refTail;
        }}
        
        // returns the src token for this ref link, or at least the closest src token possible (if rewritten):
        public SOQLLexer.Token getSrcToken() {
            if (srcIndex > -1) {
                return srcTok;
            } else {
                RefDesc node = this.prev;
                while (node != null) {
                    if (node.srcIndex > -1) {
                        return node.srcTok;
                    }
                    node = node.prev;
                }
                node = this.next;
                while (node != null) {
                    if (node.srcIndex > -1) {
                        return node.srcTok;
                    }
                    node = node.next;
                }
                // if all else fails, return the ref expr's 1st src token:
                return refExpr.names[0];
            }
        }
        
        // returns an array of all ref nodes, in order from this linked list's head to its tail:
        public RefDesc[] getFullResolvedArray() {
            RefDesc[] arr = new RefDesc[]{};
            RefDesc node = this.head;
            while (node != null) {
                arr.add(node);
                node = node.next;
            }
            return arr;
        }
        
        public String getFullResolvedString() {
            String[] parts = new String[]{};
                RefDesc node = this.head;
            while (node != null) {
                //parts.add(node.name);
                parts.add(node.normApi != null ? node.normApi : node.api != null ? node.api : node.name);
                node = node.next;
            }
            return String.join(parts, '.');
        }
        
        // returns a description of the resolved reference up to (and including) this link in the ref. note that calling this on the ref head will only
        // result in the description for that head link; for a full compund ref description, call this on the ref tail. 
        public String getResolvedDescripString() {
            // we have dual lists to iterate through to construct the resolved ref description: the source tokens array, and the resolved linked list.
            // exclusing injected tokens (srcIndex == -1), the linked list is guaranteed to be monotonically increasing with respect to srcIndex from
            // head to tail.
            SOQLLexer.Token[] srcToks = refExpr.names;
            Integer srcLen = srcToks.size();
            Integer i = 0; // current source index
            RefDesc node = head; // current node in the resolved ref linked list (traversed from head to tail)
            String[] parts = new String[]{};
                do {
                    // serialize and advance past all nodes injected at the point of the current src index:
                    while (node != null && node.srcIndex == -1) {
                        parts.add(node.name + '<injected>');
                        node = node.next;
                    }
                    
                    // calculate the src index (maybe the current src index == i, or maybe none == srcLen) corresponding to the next non-redacted & non-injected
                    // src token:
                    Integer nextNonRedactedSrcIndex = node != null ? node.srcIndex : srcLen;
                    // serialize and advance past any src tokens with src indexes before the current src index, if any - these have been redacted:
                    for (; i < nextNonRedactedSrcIndex; i++) {
                        parts.add(srcToks[i].lexeme + '<redacted>');
                    }
                    
                    // if we have a current node, then it is guaranteed to be non-injected and non-redacted, and in a 1:1 relationship with a src token. serialize
                    // and advance past it in both the resolved linked list and the src tokens array:
                    if (node != null) {
                        i = node.srcIndex + 1;
                        parts.add(node.name + (node.name != node.srcName ? '<' + node.srcName + '>' : ''));
                        node = node.next;
                    }
                    // continue until we've processed all elements in both the resolved linked list and the src tokens array:
                } while (i < srcLen || node != null);
            
            return String.join(parts, '.');
        }
        
        // TODO: re-enable
        /*
        public void setDynamic() {
            if (prev != null) {
                refErr(srcTok, 'Reference rewriter can only set the head reference as dynamic');
            }
            RefDesc node = this;
            while (node != null) {
                node.isDynamic = true;
                node = node.next;
            }
        }

        public void injectNext(String injectName) {
            RefDesc injected = new RefDesc();
            injected.refExpr = this.refExpr;
            injected.baseRefType = this.baseRefType;
            injected.prev = this;
            injected.next = this.next;
            this.next = injected;
            injected.srcIndex = -1;
            injected.srcTok = this.srcTok;
            injected.srcName = null;
            injected.name = injectName;
            injected.isDynamic = this.isDynamic;
            if (injected.next == null) {
                this.refExpr.refTail = injected;
            }
        }

        public void redactThis() {
            if (this.isHead) {
                if (this.next == null) {
                    // TODO: is this necessary?
                    refErr(srcTok, 'Reference rewriter cannot redact all reference components; if you are trying to redact before injecting, ' + 
                        'then swap the order of the calls (i.e. call injectNext first)');
                }
                this.refExpr.refHead = this.next;
            } else {
                this.prev.next = this.next;
                if (this.prev.next == null) {
                    this.refExpr.refTail = this.prev;
                }
            }
        }
        */
        
        void resolveSObject() {
            Schema.sObjectType holderType = this.holderSObjType;
            if (holderType == null) {
                return;
            }
            ReferenceProcessor refProc = refExpr.refProc;
            /*
            String holderTypeName = '' + holderType;
            String holderNamespace;
            String[] holderNameParts = holderTypeName.split('__');
            if (holderNameParts.size() == 3) {
                holderNamespace = holderNameParts[0];
            }
            */
            Schema.DescribeFieldResult fieldDesc;
            //Integer nameLen = name.length();
            Boolean isTailRef = this.isTail;
            Boolean isFieldRef = this.isTail;
            Boolean isParentRef = !isTailRef;
            Boolean isCustom;

/* mulveling-dev
            this.api = RKMock.resolveMockKey(holderType, name);
            if (api == null) {
                this.api = name;
            }
*/
            this.api = name;

            Integer apiLen = api.length();
            String[] fieldAndRel;
            // custom lkp field:
            if (api.endsWithIgnoreCase('__c')) {
                if (isParentRef && !refProc.fixLookupSuffixes) {
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; custom field found where parent relationship was expected (use __r suffix)');
                }
                isCustom = true;
                fieldAndRel = new String[]{ api, api.substring(0, apiLen - 3) + '__r' };
            // custom parent rel:
            } else if (api.endsWithIgnoreCase('__r')) {
                if (isFieldRef && !refProc.fixLookupSuffixes) {
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; custom parent relationship found where field was expected (use __c suffix)');
                }
                isCustom = true;
                fieldAndRel = new String[]{ api.substring(0, apiLen - 3) + '__c', api };
            // standard lkp field:
            } else if (api.endsWithIgnoreCase('Id')) {
                if (isParentRef && !refProc.fixLookupSuffixes) {
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; standard field found where parent relationship was expected (remove Id suffix)');
                }
                isCustom = false;
                fieldAndRel = new String[]{ api, api.substring(0, apiLen - 2) };
            // standard non-lkp field expected to be parent rel name:
            } else if (isParentRef) {
                isCustom = false;
                fieldAndRel = new String[]{ api + 'Id', api };
            // standard non-lkp field expected to be a field name:
            } else {
                isCustom = false;
                fieldAndRel = new String[]{ api, null };
            }
            
            Schema.sObjectField fieldTok = RKSecurity.resolveField(holderType, fieldAndRel[0]);
            fieldDesc = fieldTok != null ? fieldTok.getDescribe() : null;
            if (isParentRef) {
                this.normApi = fieldAndRel[1];
                if (fieldDesc != null) {
                    String fieldName = fieldDesc.getName();
                    if (fieldName.endsWithIgnoreCase('__c')) {
                        this.normApi = fieldName.substring(0, fieldName.length() - 3) + '__r';
                    } else if (fieldName.endsWithIgnoreCase('Id')) {
                        this.normApi = fieldName.substring(0, fieldName.length() - 2);
                    }
                }
            } else {
                this.normApi = fieldDesc != null ? fieldDesc.getName() : null;
            }
                            
            if (fieldDesc == null) {
                if (isFieldRef) {
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; field ' + name + ' does not exist on Object ' + holderType);
                } else {
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; parent relationship ' + name + ' does not exist on Object ' + holderType);
                }
            } else if (fieldDesc.getType() != Schema.DisplayType.Reference && isParentRef) {
                refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; resolved to a ' + fieldDesc.getType() + '-type field on Object ' + 
                       holderType + ', when a parent relationship was expected');
            } else if (isFieldRef) {
                //return fieldDesc;
                //this.fieldType = fieldDesc;
                this.fieldTypeToken = fieldTok;
                this.fieldDisplayType = fieldDesc.getType();
                this.fieldSoapType = fieldDesc.getSoapType();
            } else {
                Schema.sObjectType[] parentTypes = fieldDesc.getReferenceTo();
                if (parentTypes.size() == 1) {
                    this.sobjType = parentTypes[0];
                } else {
                    // TODO: handle polymorphic types? for now we just fail, but we should either give up validations at this point ot try to carry forward multiple
                    // possible holder types:
                    refErr(srcTok, 'Invalid sObject reference ' + getResolvedDescripString() + '; parent relationship ' + name + 
                           ' is polymorphic and this is not currently supported');
                }
            }
        }
    }
    
    public class ReferenceScanner extends AbstractVisitor {
        Boolean rawRefs = false;
        
        List<String[]> stack = new List<String[]>(5);
        Integer top = -1;
        Integer size = 5;
        
        ReferenceScanner() {
            traverseValues(false);
            this.stack[0] = new String[]{};
                }
        
        public ReferenceScanner rawRefs(Boolean rawRefs) {
            this.rawRefs = rawRefs == true;
            return this;
        }
        
        List<String[]> dblStack() {
            // double the stack size:
            stack.addAll(new List<String[]>(size));
            this.size = stack.size();
            return stack;
        }
        
        public override Boolean visit(CondExpr expr) {
            List<String[]> stack = top < size ? this.stack : dblStack();
            stack[++top] = new String[]{};
                return true;
        }
        
        public override Boolean visit(RefExpr ref) {
            if (rawRefs || ref.refHead == null) {
                stack[top].add(ref.toString());
            } else {
                stack[top].add(ref.refHead.getFullResolvedString());
            }
            return false;
        }
        
        public override void afterVisit(CondExpr expr) {
            if (top > 0) {
                stack[top - 1].addAll(stack[top]);
                top--;
            }
        }
    }

    // =============================================================================================================================
    // Cool new AST (Abstract Syntax Tree) stuff:

    public static ASTCond mintASTCond(CondExpr cond) {
        if (cond instanceof SimpleExpr) {
            SimpleExpr simple = (SimpleExpr) cond;
            return simple.nested != null ? (ASTCond) new ASTGroupCond(simple) : (ASTCond) new ASTSimpleCond(simple);
        } else {
            return new ASTCompCond(cond);
        }
    }

    global abstract class ASTCond {
        public String[] refs = new String[]{};
        public CondExpr cond;

        public ASTCond(CondExpr cond) {
            this.cond = cond;
        }

        global Boolean isGroup() {
            return this instanceof ASTGroupCond;
        }

        global Boolean isSimple() {
            return this instanceof ASTSimpleCond;
        }

        global Boolean isComp() {
            return this instanceof ASTCompCond;
        }

        global Boolean isAnd() {
            return cond instanceof AndExpr;
        }

        global Boolean isOr() {
            return cond instanceof OrExpr;
        }

        global Boolean isNot() {
            return cond instanceof NotExpr;
        }

        global abstract String getType();
    }

    global class ASTCompCond extends ASTCond {
        public ASTCompCond(CondExpr cond) {
            super(cond);
        }

        global override String getType() {
            if (cond instanceof AndExpr) {
                return 'and';
            } else if (cond instanceof OrExpr) {
                return 'or';
            } else if (cond instanceof NotExpr) {
                return 'not';
            }
            return null;
        }
    }

    global class ASTSimpleCond extends ASTCond {
        global ASTReference ref;
        global SOQLLexer.Token op;
        global ASTValue val;

        public ASTSimpleCond(SimpleExpr simple) {
            super(simple);
            this.ref = new ASTReference(simple.ref);
            this.op = simple.relOp;
            this.val = new ASTValue(simple.val);
        }

        global override String getType() {
            return 'simple';
        }
    }

    global class ASTGroupCond extends ASTCond {
        global ASTCond nested;

        public ASTGroupCond(SimpleExpr groupCond) {
            super(groupCond);
            this.nested = mintASTCond(groupCond.nested);
        }

        global override String getType() {
            return 'group';
        }
    }

    global class ASTReference {
        public RefExpr ref;

        public ASTReference(RefExpr ref) {
            this.ref = ref;
        }

        global Integer getPathSize() {
            return ref.names.size();
        }

        global String getLexicalPath() {
            return ref.toString();
        }

        global String getNormalizedPath() {
            if (ref.refHead == null) {
                return null;
            }
            return ref.refHead.getFullResolvedString();
        }

        global String getBestPath() {
            if (ref.refHead == null) {
                return ref.toString(); // lexical path
            } else {
                return ref.refHead.getFullResolvedString(); // normalized path
            }
        }
    }

    global class ASTValue {
        public Value val;
        global ValueElmt scalar;
        global ValueElmt[] vector;

        public ASTValue(Value val) {
            this.val = val;
            if (val instanceof ValueList) {
                this.vector = ((ValueList) val).elements;
            } else {
                this.scalar = (ValueElmt) val;
            }
        }

        global Boolean isList() {
            return vector != null;
        }

        global ASTValue[] getListValues() {
            ASTValue [] vals = new ASTValue[]{};
            for (ValueElmt elmt : vector) {
                vals.add(new ASTValue(elmt));
            }
            return vals;
        }

        global Boolean isLiteral() {
            return this.scalar != null && this.scalar.param == null;
        }

        global Boolean isNamedParam() {
            return this.scalar != null && this.scalar.paramName != null;
        }

        global Boolean isUnboundNamedParam() {
            return this.scalar != null && this.scalar.paramName != null && this.scalar.paramResolvedValue == null;
        }

        global Boolean isIndexedParam() {
            return this.scalar != null && this.scalar.paramIndex != null;
        }

        global Boolean isAnonParam() {
            return this.scalar != null && this.scalar.paramAnon != null;
        }
    }

    global virtual class ASTVisitor extends AbstractVisitor {
        //Boolean rawRefs = false;
        global List<ASTCond> stack = new List<ASTCond>(5);
        global Integer top = -1;
        Integer size = 5;
        
        global ASTVisitor() {
            traverseValues(true);
        }

        global virtual void reset() {
            this.stack = new List<ASTCond>(5);
            this.top = -1;
            this.size = 5;
        }

        global ASTCond top() {
            return stack[top];
        }

        global ASTCond[] parents() {
            ASTCond[] parents = new ASTCond[]{};
            for (Integer i = 0; i < top; i++) {
                parents.add(stack[i]);
            }
            return parents;
        }

        global virtual void onStart(ASTCond root) {}
        global virtual void onCond(ASTCond cond) {}
        global virtual void onLeaveCond(ASTCond cond) {}
        global virtual void onValue(ASTValue val) {}
        global virtual void onReference(ASTReference ref) {}
        global virtual void onFinish(ASTCond root) {}
        
        List<ASTCond> dblStack() {
            // double the stack size:
            stack.addAll(new List<ASTCond>(size));
            this.size = stack.size();
            return stack;
        }
        
        public override Boolean visit(CondExpr expr) {
            if (expr instanceof SimpleExpr && ((SimpleExpr) expr).nested != null) {
                return true;
            }
            List<ASTCond> stack = top + 1 < size ? this.stack : dblStack();
            ASTCond cond = mintASTCond(expr);
            stack[++top] = cond;
            if (top == 0) {
                onStart(cond);
            }
            onCond(cond);
            return true;
        }

        public override void afterVisit(CondExpr expr) {
            if (expr instanceof SimpleExpr && ((SimpleExpr) expr).nested != null) {
                return;
            }
            Integer oldTop = top;
            try {
                onLeaveCond(stack[top]);
            } finally {
                if (top > 0) {
                    stack[top - 1].refs.addAll(stack[top].refs);
                    top--;
                }
            }
            if (oldTop == 0) {
                onFinish(stack[oldTop]);
            }
        }
        
        public override Boolean visit(RefExpr ref) {
            ASTReference astRef = new ASTReference(ref);
            stack[top].refs.add(astRef.getBestPath());
            onReference(astRef);
            return true;
        }
        

        public override Boolean visit(Value abstractVal) {
            onValue(new ASTValue(abstractVal));
            return true;
        }
    }

    // =============================================================================================================================
    
    public class EvalDebug extends Visitor {
        Boolean rawRefs = false;
        
        public Boolean[] results = new Boolean[]{};
        public CondExpr[] parts = new CondExpr[]{};
                
        public String[] printResults() {
            String[] lines = new String[]{};
            for (Integer i=0; i < results.size(); i++) {
                lines.add(results[i] + ': ' + parts[i].ser());
            }
            return lines;
        }
        
        public override Boolean visit(OrExpr expr) {
            results.add(expr.eval);
            parts.add(expr);
            return true;
        }
        
        public override Boolean visit(AndExpr expr) {
            results.add(expr.eval);
            parts.add(expr);
            return true;
        }
        
        public override Boolean visit(NotExpr expr) {
            results.add(expr.eval);
            parts.add(expr);
            return true;
        }
        
        public override Boolean visit(SimpleExpr expr) {
            results.add(expr.eval);
            parts.add(expr);
            return expr.nested != null;
        }
    }
    
    static final Object UNDEFINED_VAL = new UndefinedVal();
    class UndefinedVal {}
    
    global class ValueResolver extends Visitor {
        // Params may be a Map<String,Object> (named param values), an Object[] array (indexed and/or anonymous params), or a simple
        // value (treated as a single-element array):
        Map<String, Object> namedParams;
        Map<String, Object> namedParamsLC;
        Object[] indexedParams;
        Boolean clobberPrior = false;
        Boolean clobberPriorAndAnons = false;
        SOQLLexer.Token[] unboundAnonParams = new SOQLLexer.Token[]{};
            
            // this stack is maintained and used for just-in-time type resolving, in cases where the anchor type is set:
            SimpleExpr[] simpleExprStack = new SimpleExpr[]{};
                
                Integer anonCounter = 0;
        
        ReferenceProcessor refProc;
        LocalReBindPool reBindPool;
        
        // TODO: add capability for case-insensitive params?
        global ValueResolver(Map<String, Object> namedParams) {
            this.namedParams = namedParams;
        }
        
        global ValueResolver(Object[] indexedParams) {
            this.indexedParams = indexedParams;
        }
        
        global ValueResolver(Map<String, Object> namedParams, Object[] indexedParams) {
            this.namedParams = namedParams;
            this.indexedParams = indexedParams;
        }
        
        global ValueResolver(Object bindDis) {
            if (bindDis instanceof Object[]) {
                this.indexedParams = (Object[]) bindDis;
            } else if (bindDis instanceof Map<String, Object>) {
                this.namedParams = (Map<String, Object>) bindDis;
            } else {
                this.indexedParams = new Object[]{ bindDis };
                    }
        }
        
        /*
        @deprecated
        global ValueResolver typeValidations(Boolean val) {
            return this;
        }
        
        @deprecated
        global ValueResolver refProcessing(SOQLParser parser) {
            this.refProc = parser.refProc;
            return this;
        } 
        */
        
        global ValueResolver refProc(ReferenceProcessor refProc) {
            this.refProc = refProc;
            if (refProc == null) {
                this.refProc = new ReferenceProcessor();
            }
            return this;
        }

        global ValueResolver reBindPool(LocalReBindPool reBindPool) {
            this.reBindPool = reBindPool;
            return this;
        } 
        
        global ValueResolver clobberPrior(Boolean clobberPrior) {
            this.clobberPrior = clobberPrior == true;
            return this;
        }

        global ValueResolver clobberPriorAndAnons(Boolean clobberPriorAndAnons) {
            this.clobberPriorAndAnons = clobberPriorAndAnons == true;
            return this;
        }
        
        // !! this must be called before a traversal using this type of visitor:
        ValueResolver normalizeNamedParams() {
            if (namedParams != null) {
                namedParamsLC = new Map<String, Object>();
                for (String key : namedParams.keySet()) {
                    namedParamsLC.put(key.toLowerCase(), namedParams.get(key));
                }
            }
            return this;
        }
        
        global virtual override Boolean visit(SimpleExpr expr) {
            simpleExprStack.add(expr);
            return true;
        }
        
        global virtual override void afterVisit(SimpleExpr expr) {
            simpleExprStack.remove(simpleExprStack.size() - 1);
        }
        
        global virtual override Boolean visit(ValueElmt elmt) {
            // anonymous value bindings cannot be erased:
            if ((clobberPrior && elmt.paramAnon == null) || clobberPriorAndAnons) { //&& elmt.paramResolvedValue != null) {
                elmt.paramResolvedValue = null;
                if (elmt.param != null) {
                    // reset the eval cache since we've clobbered the param-resolved value:
                    elmt.evald = false;
                }
                // We must also clear any prior local re-binds that had been accepted:
                elmt.localReBind = null;
                //return false;
            }
            Object rawBindVal = UNDEFINED_VAL;
            Integer anonParamIndex;
            if (elmt.param != null) {
                if (elmt.paramName != null && namedParams != null && namedParamsLC.containsKey(elmt.paramName.lexeme.toLowerCase())) {
                    rawBindVal = namedParamsLC.get(elmt.paramName.lexeme.toLowerCase());
                } else if (elmt.paramIndex != null && indexedParams != null && elmt.paramIndexIntVal < indexedParams.size()) {
                    rawBindVal = indexedParams[elmt.paramIndexIntVal];
                // once an anonymous param is bound to a value, that value will stick forever:
                } else if (elmt.paramAnon != null && elmt.paramResolvedValue == null && indexedParams != null && anonCounter < indexedParams.size()) {
                    rawBindVal = indexedParams[anonParamIndex = anonCounter++];
                }
                if (rawBindVal === UNDEFINED_VAL && elmt.paramAnon != null) {
                    unboundAnonParams.add(elmt.paramAnon);
                }
            }
            //if (elmt.paramName != null && params.containsKey(elmt.paramName.lexeme)) {
            if (rawBindVal !== UNDEFINED_VAL) {
                // reset the eval cache since we're binding this param to a new value:
                elmt.evald = false;
                
                // just-in-time and if necessary (i.e. if simpleExpr.ref.refProc is null, then simpleExpr.ref.fieldTypeToken 
                // is also guaranteed to be null), run this serializer's ReferenceProcessor instance over simpleExpr.ref:
                // TODO: should we also check for incompatible baseRefType? (no; let user shoot themselves in foot):
                SimpleExpr simp = simpleExprStack[simpleExprStack.size() - 1];
                if (simp.ref.refProc == null && refProc.baseRefType != null) {
                    // this call may throw a ReferenceException, depending on this.refProc's settings:
                    refProc.visit(simp.ref);
                }
                //Schema.DescribeFieldResult targetType = simp.ref.fieldType;
                Schema.DescribeFieldResult targetType = simp.ref.fieldTypeToken.getDescribe();
                Object[] vals;
                ValueList resolvedValueList;
                Boolean startValueList = true;
                if (rawBindVal instanceof Object[]) {
                    vals = (Object[]) rawBindVal;
                } else if (rawBindVal instanceof Id || rawBindVal instanceof String || 
                        rawBindVal instanceof Decimal || rawBindVal instanceof Date || 
                        rawBindVal instanceof DateTime || rawBindVal instanceof sObject) {
                    startValueList = false;
                    vals = new Object[]{ rawBindVal };
                } else if (rawBindVal instanceof Set<Id>) {
                    vals = new List<Id>((Set<Id>) rawBindVal);
                } else if (rawBindVal instanceof Set<String>) {
                    vals = new List<String>((Set<String>) rawBindVal);
                } else if (rawBindVal instanceof Set<Decimal>) {
                    vals = new List<Decimal>((Set<Decimal>) rawBindVal);
                } else if (rawBindVal instanceof Set<Integer>) {
                    vals = new List<Integer>((Set<Integer>) rawBindVal);
                } else if (rawBindVal instanceof Set<Date>) {
                    vals = new List<Date>((Set<Date>) rawBindVal);
                } else if (rawBindVal instanceof Set<Double>) {
                    vals = new List<Double>((Set<Double>) rawBindVal);
                } else if (rawBindVal instanceof Set<Long>) {
                    vals = new List<Long>((Set<Long>) rawBindVal);
                } else if (rawBindVal instanceof Set<DateTime>) {
                    vals = new List<DateTime>((Set<DateTime>) rawBindVal);
                } else if (rawBindVal instanceof Set<Boolean>) {
                    vals = new List<Boolean>((Set<Boolean>) rawBindVal);
                } else if (rawBindVal instanceof List<sObject>) {
                    vals = new List<sObject>((Set<sObject>) rawBindVal);
                } else {
                    // TODO: consider making this branch an error:
                    startValueList = false;
                    vals = new Object[]{ rawBindVal };
                }
                
                if (startValueList) {
                    elmt.paramResolvedValue = resolvedValueList = new ValueList();
                    resolvedValueList.elements = new ValueElmt[]{};
                 }
                
                Schema.DisplayType fineType = targetType != null ? targetType.getType() : null;
                Integer opType = simp.relOp.ttype;
                // If this ValueElmt was previously bound to a LocalReBind, and that reBind's vals reference-match the 
                // new vals, then we should keep the prior LocalReBind:
                // TODO: This kind of check-duplicate logic could be further improved to cut down even more on needless 
                // burning of LocalReBinds for the same vals:
                if (elmt.localReBind != null) {
                    if (elmt.localReBind.vals === vals) {
                        return true;
                    // If vals has changed, we must clear out the old reBind:
                    } else {
                        // TODO: Destroy/reclaim this re-bind if it or its values are no longer referenced?
                        elmt.localReBind = null;
                    }
                }
                if (this.reBindPool != null && startValueList && (fineType == Schema.DisplayType.ID || fineType == Schema.DisplayType.Reference) && 
                        (opType == SOQLLexer.KW_IN || opType == SOQLLexer.KW_NOT || opType == SOQLLexer.EQUALS || opType == SOQLLexer.NOT_EQUALS)) {
                    elmt.localReBind = this.reBindPool.accept(vals);
                    if (elmt.localReBind != null) {
                        return true;
                    }
                }

                ValueElmt nextElmt = new ValueElmt();
                for (Object val : vals) {
                    if (targetType != null && refProc != null && refProc.baseRefType != null) {
                        if (refProc.paramBindMode == PARAM_BIND_MODE_STRICT) {
                            checkParamBindingValue(simp, elmt, anonParamIndex, targetType, val);
                        } else if (refProc.paramBindMode == PARAM_BIND_MODE_LOOSE) {
                            val = convertParamBindingValue(simp, elmt, anonParamIndex, targetType, val);
                        }
                        // else no further value type-coercion/checking if mode == PARAM_BIND_MODE_BLIND...
                    }
                    
                    SOQLLexer.Token loc = elmt.loc;
                    nextElmt = new ValueElmt();
                    nextElmt.loc = loc;
                    if (val == null) {
                        nextElmt.kwLit = newInjectedToken(SOQLLexer.KW_NULL, 'null', loc);
                    } else if (val == true) {
                        nextElmt.kwLit = newInjectedToken(SOQLLexer.KW_TRUE, 'true', loc);
                    } else if (val == false) {
                        nextElmt.kwLit = newInjectedToken(SOQLLexer.KW_FALSE, 'false', loc);
                        // Apex implements instanceof on number values as a precision-compatibility (sort of) operator; Decimal is the most generic Apex number type:
                    } else if (val instanceof Decimal) {
                        try {
                            nextElmt.numberLit = (Decimal) val;
                            // MathException will be thrown if you try to convert the Double values: Infinity, -Infinity or NaN to a Decimal
                        } catch (System.MathException me) {
                            nextElmt.specialNumberLit = (Double) val;
                        }
                        // if val is instanceof Id, then it is also instanceof String:
                    } else if (val instanceof String) {
                        nextElmt.isString = true;
                        //nextElmt.resolvedStringValue = nextElmt.stringBindValue = (String) val;
                        // !! reset resolvedStringValue in case it needs to be recompiled from stringBindValue for a LIKE op regexp:
                        nextElmt.resolvedStringValue = null;
                        nextElmt.stringBindValue = (String) val;
                    } else if (val instanceof Date) {
                        nextElmt.dateLit = (Date) val;
                    } else if (val instanceof DateTime) {
                        nextElmt.dateTimeLit = (DateTime) val;
                    } else {
                        typeErr(loc, 'Illegal value type bound to parameter :' + elmt.param.lexeme + ' [' + val + ']');
                    }
                    
                    if (resolvedValueList != null) {
                        resolvedValueList.elements.add(nextElmt);
                    } else {
                        elmt.paramResolvedValue = nextElmt;
                        break;
                    }
                    
                    // TODO: add ability to bind currency values and date forumlas...
                    
                    // TODO: type validations!!
                    
                } // for (Object val : vals)
            }
            return true;
        }
    }
    
    // yyy-mm-dd
    static final Pattern JSONDatePatt = Pattern.compile('(\\d{4})\\s*-\\s*(\\d{1,2})\\s*-\\s*(\\d{1,2})'); //'
    // 2016-02-22T20:34:35.179Z
    static final Pattern JSONDateTimePatt = Pattern.compile('(\\d{4})\\s*-\\s*(\\d{1,2})\\s*-\\s*(\\d{1,2})T(\\d{1,2}):(\\d{1,2}):(\\d{1,2})(\\.(\\d{1,4}))?Z'); //'
    // e.g. Tue Feb 23 2016 10:30:34 GMT-0500 (EST)
    static final Pattern JavaScriptDatePatt = Pattern.compile('(?i)^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat)\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+(\\d{1,2})\\s+(\\d{4})\\b'); //'
    static final Pattern JavaScriptDateTimePatt = Pattern.compile('(?i)^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat)\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+(\\d{1,2})\\s+(\\d{4})\\s+(\\d{1,2}):(\\d{1,2}):(\\d{1,2})\\s+GMT(-|\\+)(\\d{2})(\\d{2})\\b'); //'
    
    static final Map<String, Integer> JSMonthMap = new Map<String, Integer>{
        'jan' => 1,
            'feb' => 2,
            'mar' => 3,
            'apr' => 4,
            'may' => 5,
            'jun' => 6,
            'jul' => 7,
            'aug' => 8,
            'sep' => 9,
            'oct' => 10,
            'nov' => 11,
            'dec' => 12
            };
                
    static final Double NaN = Double.valueOf('NaN');
    static final Double Infinity = Double.valueOf('Infinity');
    static final Double NegInfinity = Double.valueOf('-Infinity');
    
    static void checkParamBindingValue(SimpleExpr parent, ValueElmt elmt, Integer anonParamIndex, Schema.DescribeFieldResult lhsType, Object val) {
        Schema.SOAPType lhsSoapType = lhsType.getSOAPType();
        if (lhsSoapType == SOAPType.Double || lhsSoapType == SOAPType.Integer) {
            if (val != null && !(val instanceof Double)) {
                typeErr(elmt.loc, 'Expected a number value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.Boolean) {
            if (val != null && !(val instanceof Boolean)) {
                typeErr(elmt.loc, 'Expected a boolean value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.String) {
            if (val != null && !(val instanceof String)) {
                typeErr(elmt.loc, 'Expected a string value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.ID) {
            if (val != null && !(val instanceof String)) {
                typeErr(elmt.loc, 'Expected an id value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            } else {
                try {
                    Id idVal = Id.valueOf(String.valueOf(val));
                } catch (System.StringException idErr) {
                    typeErr(elmt.loc, 'Expected an id value for ' + printParam(elmt, anonParamIndex) + 
                            '; got non-id string value [' + val + ']');
                }
            }
        } else if (lhsSoapType == SOAPType.Date) {
            if (val != null && !(val instanceof Date)) {
                typeErr(elmt.loc, 'Expected a date value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.DateTime) {
            if (val != null && !(val instanceof DateTime)) {
                typeErr(elmt.loc, 'Expected a date time value for ' + printParam(elmt, anonParamIndex) + 
                        '; got ' + printValType(val) + ' value [' + val + ']');
            }
        } else {
            typeErr(elmt.loc, 'Cannot bind ' + printParam(elmt, anonParamIndex) + ' to a left-hand side of type: ' + 
                    lhsSoapType.name());
        }
    }
    
    @testVisible
    static String printValType(Object val) {
        if (val instanceof String) {
            return 'string';
        } else if (val instanceof Double) {
            return 'number';
        } else if (val instanceof Boolean) {
            return 'boolean';
        } else if (val instanceof Date) {
            return 'date';
        } else if (val instanceof DateTime) {
            return 'date time';
        } else if (val instanceof Blob) {
            return 'blob';
        } else if (val instanceof Object[]) {
            return 'array';
        } else {
            return 'object';
        }
    }
    
    static Object convertParamBindingValue(SimpleExpr parent, ValueElmt elmt, Integer anonParamIndex, Schema.DescribeFieldResult lhsType, Object val) {
        Schema.SOAPType lhsSoapType = lhsType.getSOAPType();
        if (lhsSoapType == SOAPType.Double || lhsSoapType == SOAPType.Integer) {
            if (val == null) {
                return null;
            } else if (val instanceof Double) {
                return val;
            } else if (val instanceof String) {
                try {
                    return Decimal.valueOf((String) val);
                } catch (System.TypeException decErr) {
                    // give NaN, Infinity, -Infinity a chance in case we're using this for in-memory eval:
                    try {
                        return Double.valueOf((String) val);
                    } catch (System.TypeException dubErr) {
                        typeErr(elmt.loc, 'Expected a number value for ' + printParam(elmt, anonParamIndex) + 
                                '; got string that does not match the JSON or JavaScript number formats [' + val + ']');
                    }
                }
            } else if (val instanceof Boolean) {
                return val == true ? 1 : 0;
                // TODO: Date, DateTime?
            } else {
                typeErr(elmt.loc, 'Expected a number value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.Boolean) {
            if (val == null) {
                return false;
            } else if (val instanceof Boolean) {
                return val;
            } else if (val instanceof String) {
                if (val == 'true' || val == '1') {
                    return true;
                } else if (val == 'false' || val == '0' || val == null) {
                    return false;
                } else {
                    typeErr(elmt.loc, 'Expected a boolean value for ' + printParam(elmt, anonParamIndex) + 
                            '; got incompatible string value [' + val + ']');
                }
            } else if (val instanceof Double) {
                return val != 0;
            } else {
                typeErr(elmt.loc, 'Expected a boolean value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.String) {
            if (val == null) {
                return null;
                // note that an Id is always an instanceof string:
            } else if (val instanceof String) {
                return String.valueOf(val);
            } else if (val instanceof Double) {
                Decimal decVal;
                try {
                    // !! If val is a special Double value (Infinity, NegInfinity, or NaN) it can throw a 
                    // math error on Decimal conversion:
                    decVal = (Decimal) val;
                } catch (MathException me) {
                    typeErr(elmt.loc, 'Invalid number value for ' + printParam(elmt, anonParamIndex) + 
                        '; cannot convert [' + val + '] to decimal');
                }
                // print out decimals in full precision without scientific notation:
                return decVal.toPlainString();
            } else if (val instanceof Boolean) {
                return val == true ? 'true' : 'false';
            } else if (val instanceof Date) {
                // JSON format (e.g. 2016-07-21):
                return DateTime.newInstanceGmt((Date) val, Time.newInstance(0, 0, 0, 0)).formatGmt('yyyy-MM-dd');
            } else if (val instanceof DateTime) {
                // JSON format (e.g. 2016-02-22T20:34:35.179Z):
                DateTime dateTimeVal = (DateTime) val;
                return dateTimeVal.formatGmt('yyyy-MM-dd') + 'T' + dateTimeVal.formatGmt('HH:mm:ss.SSS') + 'Z';
            } else {
                typeErr(elmt.loc, 'Expected a string value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.ID) {
            if (val == null) {
                return null;
            } else if (val instanceof String) {
                try {
                    return Id.valueOf(String.valueOf(val));
                } catch (System.StringException idErr) {
                    typeErr(elmt.loc, 'Expected an id value for ' + printParam(elmt, anonParamIndex) + 
                            '; got incompatible string value [' + val + ']');
                }
            } else if (val instanceof sObject) {
                return ((sObject) val).Id;
            } else {
                typeErr(elmt.loc, 'Expected an id value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.Date) {
            if (val == null) {
                return null;
            } else if (val instanceof String) {
                Matcher m = JSONDatePatt.matcher(((String) val).trim());
                if (m.matches()) {
                    Integer year = Integer.valueOf(m.group(1));
                    Integer month = Integer.valueOf(m.group(2));
                    Integer day = Integer.valueOf(m.group(3));
                    return Date.newInstance(year, month, day);
                } else {
                    m = JavaScriptDatePatt.matcher(((String) val).trim());
                    if (m.find()) {
                        Integer year = Integer.valueOf(m.group(3));
                        Integer day = Integer.valueOf(m.group(2));
                        Integer month = JSMonthMap.get(m.group(1).toLowerCase());
                        return Date.newInstance(year, month, day);
                    } else {
                        typeErr(elmt.loc, 'Expected a date value for ' + printParam(elmt, anonParamIndex) + 
                                '; got string that does not match the JSON or JavaScript formats [' + val + ']');
                    }
                }
            } else if (val instanceof Decimal) {
                Decimal dval = (Decimal) val;
                if (dval.round() != dval) {
                    typeErr(elmt.loc, 'Expected a date value for ' + printParam(elmt, anonParamIndex) + 
                            '; got decimal number [' + val + ']');
                } else {
                    return DateTime.newInstance(dval.longValue()).date();
                }
            } else if (val instanceof DateTime) {
                return ((DateTime) val).date();
            } else if (!(val instanceof Date)) {
                typeErr(elmt.loc, 'Expected a date value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else if (lhsSoapType == SOAPType.DateTime) {
            if (val == null) {
                return null;
            } else if (val instanceof String) {
                Matcher m = JSONDateTimePatt.matcher(((String) val).trim());
                if (m.matches()) {
                    Integer year = Integer.valueOf(m.group(1));
                    Integer month = Integer.valueOf(m.group(2));
                    Integer day = Integer.valueOf(m.group(3));
                    Integer hour = Integer.valueOf(m.group(4));
                    Integer min = Integer.valueOf(m.group(5));
                    Integer sec = Integer.valueOf(m.group(6));
                    Integer millis = 0;
                    if (m.group(7) != null) {
                        Integer numDigits = m.group(8).length();
                        Integer secFraction = Integer.valueOf(m.group(8));
                        millis = (secFraction * (numDigits == 1 ? 100.0 : numDigits == 2 ? 10.0 : numDigits == 3 ? 1.0 : 0.1)).round().intValue();
                    }
                    return DateTime.newInstanceGmt(Date.newInstance(year, month, day), Time.newInstance(hour, min, sec, millis));
                } else {
                    m = JavaScriptDateTimePatt.matcher(((String) val).trim());
                    if (m.find()) {
                        Integer year = Integer.valueOf(m.group(3));
                        Integer day = Integer.valueOf(m.group(2));
                        Integer month = JSMonthMap.get(m.group(1).toLowerCase());
                        Integer hour = Integer.valueOf(m.group(4));
                        Integer min = Integer.valueOf(m.group(5));
                        Integer sec = Integer.valueOf(m.group(6));
                        Integer offsetPolarity = m.group(7) == '+' ? -1 : 1;
                        Integer offsetHour = Integer.valueOf(m.group(8));
                        Integer offsetMin = Integer.valueOf(m.group(9));
                        DateTime gmtTime = DateTime.newInstanceGmt(year, month, day, hour, min, sec);
                        gmtTime = gmtTime.addHours(offsetHour * offsetPolarity);
                        gmtTime = gmtTime.addMinutes(offsetMin * offsetPolarity);
                        return gmtTime;
                    } else {
                        typeErr(elmt.loc, 'Expected a date time value for ' + printParam(elmt, anonParamIndex) + 
                                '; got string that does not match the JSON or JavaScript formats [' + val + ']');
                    }
                }
            } else if (val instanceof Decimal) {
                Decimal dval = (Decimal) val;
                if (dval.round() != dval) {
                    typeErr(elmt.loc, 'Expected a date time value for ' + printParam(elmt, anonParamIndex) + 
                            '; got decimal number [' + val + ']');
                } else {
                    return DateTime.newInstance(dval.longValue());
                }
            } else if (val instanceof Date) {
                return DateTime.newInstanceGmt((Date) val, Time.newInstance(0, 0, 0, 0));
            } else if (!(val instanceof DateTime)) {
                typeErr(elmt.loc, 'Expected a date time value for ' + printParam(elmt, anonParamIndex) + 
                        '; got incompatible value [' + val + ']');
            }
        } else {
            typeErr(elmt.loc, 'Cannot bind ' + printParam(elmt, anonParamIndex) + ' to a left-hand side of type: ' + 
                    lhsSoapType.name());
        }
        return val;
    }
    
    static String printParam(ValueElmt elmt, Integer anonParamIndex) {
        if (elmt.paramAnon != null) {
            return anonParamIndex != null ? 'anonymous parameter #' + (anonParamIndex + 1) : 'anonymous parameter';
        }
        return 'parameter :' + elmt.param.lexeme;
    }
    
    static SOQLLexer.Token newInjectedToken(Integer ttype, String lexeme, SOQLLexer.Token loc) {
        SOQLLexer.Token tok = loc.clone();
        tok.ttype = ttype;
        tok.lexeme = lexeme;
        tok.injected = true;
        return tok;
    }

    static SOQLLexer.Token newInjectedToken(Integer ttype, String lexeme) {
        SOQLLexer.Token tok = new SOQLLexer.Token();
        tok.ttype = ttype;
        tok.lexeme = lexeme;
        tok.injected = true;
        tok.index = -1;
        tok.line = -1;
        tok.col = -1;
        return tok;
    }
    
    static final Set<Integer> relationalOpTypes = new Set<Integer>{
        SOQLLexer.LESS_THAN_EQUALS, SOQLLexer.LESS_THAN,
        SOQLLexer.GREATER_THAN_EQUALS, SOQLLexer.GREATER_THAN
    };
                
    // This serializer outputs a parsed condition expression in strict SOQL syntax. Any transformations and/or parameter bindings should be performed
    // before this:
    global virtual class Serializer extends Visitor {
        // this stack is to aid type checking at the Value level; values can easlily look to the top of the stack to get their target field and type.
        // with the current implementation this stack can only be a max of 1-deep, but if queries can be nested in the future (i.e. values list from nested
        // query) then it can become deeper:
        SimpleExpr[] simpleExprStack = new SimpleExpr[]{};
            // used for just-in-time resolving of any missing ref/field type information:
            ReferenceProcessor refProc;
        
        global Serializer(Schema.sObjectType baseRefType) {
            this.refProc = new ReferenceProcessor(baseRefType);
        }
        
        global Serializer(ReferenceProcessor refProc) {
            //System.assert(refProc != null, 'Serializer<init> - Reference Processor cannot be null');
            this.refProc = refProc;
            if (refProc == null) {
                this.refProc = new ReferenceProcessor();
            }
        }
        
        global Serializer strictTypes(Schema.sObjectType baseRefType) {
            if (refProc.baseRefType != baseRefType) {
                //this.refProc = new ReferenceProcessor(baseRefType);
                this.refProc = new ReferenceProcessor(refProc); // preserve prior settings
                this.refProc.baseRefType = baseRefType;
            }
            refProc.strictRefs = true;
            return this;
        }
        
        global virtual override Boolean visit(OrExpr orExpr) {
            orExpr.serLvlOverride = null;
            if (orExpr.isEmpty()) {
                orExpr.ser = '';
                return false;
            } else {
                return true;
            }
        }
        
        global virtual override void afterVisit(OrExpr orExpr) {
            Integer len = orExpr.children.size();
            String[] terms = new String[len];
            for (Integer i=0; i < len; i++) {
                CondExpr t = orExpr.children[i];
                if (t.isEmpty()) {
                    continue;
                }
                // if it's a simple expr with a nested cond, then yank out the actual cond that's nested (potentially multiple levels of nesting) and evaluate that instead:
                if (t.lvl == LVL_SIMPLE) {
                    t = ((SimpleExpr) t).unwrap();
                }
                // below here, a simple expr will not be nested; it must be a relational/equality expr which does not require parenthesis wrapping in this context:
                if (t.serLvl < LVL_SIMPLE) {
                    terms[i] = len > 1 ? '(' + t.ser + ')' : t.ser;
                } else if (t.serLvl == LVL_SIMPLE) {
                    terms[i] = t.ser;
                } else {
                    System.assert(false, 'Encountered element cannot be term of an OR expression: ' + t.ser);
                }
            }
            if (len > 1) {
                orExpr.ser = String.join(terms, ' OR ');
            } else {
                orExpr.ser = terms[0];
                orExpr.serLvlOverride = orExpr.children[0].serLvl;
            }
        }
        
        global virtual override Boolean visit(AndExpr andExpr) {
            andExpr.serLvlOverride = null;
            if (andExpr.isEmpty()) {
                andExpr.ser = '';
                return false;
            } else {
                return true;
            }
        }
        
        global virtual override void afterVisit(AndExpr andExpr) {
            Integer len = andExpr.children.size();
            String[] terms = new String[len];
            for (Integer i=0; i < len; i++) {
                CondExpr t = andExpr.children[i];
                if (t.isEmpty()) {
                    continue;
                }
                // if it's a simple expr with a nested cond, then yank out the actual cond that's nested (potentially multiple levels of nesting) and evaluate that instead:
                if (t.lvl == LVL_SIMPLE) {
                    t = ((SimpleExpr) t).unwrap();
                }
                // below here, a simple expr will not be nested; it must be a relational/equality expr which does not require parenthesis wrapping in this context:
                if (t.serLvl < LVL_SIMPLE) {
                    terms[i] = len > 1 ? '(' + t.ser + ')' : t.ser;
                } else if (t.serLvl == LVL_SIMPLE) {
                    terms[i] = t.ser;
                } else {
                    System.assert(false, 'Encountered element cannot be term of an AND expression: ' + t.ser);
                }
            }
            if (len > 1) {
                andExpr.ser = String.join(terms, ' AND ');
            } else {
                andExpr.ser = terms[0];
                andExpr.serLvlOverride = andExpr.children[0].serLvl;
            }
        }
        
        global virtual override Boolean visit(NotExpr notExpr) {
            notExpr.serLvlOverride = null;
            if (notExpr.isEmpty()) {
                notExpr.ser = '';
                return false;
            } else {
                return true;
            }
        }
        
        global virtual override void afterVisit(NotExpr notExpr) {
            CondExpr t = notExpr.operand;
            // if it's a simple expr with a nested cond, then yank out the actual cond that's nested (potentially multiple levels of nesting) and evaluate that instead:
            if (t.lvl == LVL_SIMPLE) {
                t = ((SimpleExpr) t).unwrap();
            }
            // below here, a simple expr will not be nested; it must be a relational/equality expr which does not require parenthesis wrapping in this context:
            if (t.serLvl < LVL_SIMPLE) {
                notExpr.ser = 'NOT (' + t.ser + ')';
            } else if (t.serLvl == LVL_SIMPLE) {
                notExpr.ser = 'NOT ' + t.ser;
            } else {
                System.assert(false, 'Encountered element cannot be operand of a NOT expression: ' + t.ser);
            }
        }
        
        global virtual override Boolean visit(SimpleExpr simpleExpr) {
            simpleExpr.serLvlOverride = null;
            if (simpleExpr.isEmpty()) {
                simpleExpr.ser = '';
                return false;
            } else {
                // translate the beginsWith/endsWith/contains ops into a SOQL LIKE condition:
                Boolean isBeginsWith = simpleExpr.relOp != null 
                        && (simpleExpr.relOp.ttype == SOQLLexer.KW_BEGINS_WITH || simpleExpr.relOp.ttype == SOQLLexer.KW_STARTS_WITH),
                    isEndsWith = simpleExpr.relOp != null && simpleExpr.relOp.ttype == SOQLLexer.KW_ENDS_WITH,
                    isContains = simpleExpr.relOp != null && simpleExpr.relOp.ttype == SOQLLexer.KW_CONTAINS;
                // translate beginsWith/endsWith/contains operators:
                if (isBeginsWith || isEndsWith || isContains) {
                    
                    Value srcVal = simpleExpr.val;
                    ValueElmt srcElmt;
                    do {
                        if (srcVal instanceof ValueList) {
                            srcElmt = ((ValueList) srcVal).elements[0];
                        } else {
                            srcElmt = (ValueElmt) srcVal;
                        }
                        // if the ValueElmt is a param, then its param-resolved Value may be a simple ValueElmt or a ValueList, so
                        // reiterate the above logic on that param-resolved value:
                        if (srcElmt.paramResolvedValue != null) {
                            srcVal = srcElmt.paramResolvedValue;
                            continue;
                        } else {
                            break;
                        }
                    } while (true);
                    
                    ValueElmt transElmt = new ValueElmt();
                    transElmt.loc = srcElmt.loc.clone();
                    transElmt.loc.injected = true;
                    transElmt.isString = true;
                    if (srcElmt.isString == true) {
                        if (srcElmt.stringLitParts != null) {
                            // keep all code == 2 escapes ('%' or '_')
                            // find all '%' or '_' in literal parts and backslash escape them
                            // tack-on '%' prefix/suffix parts (code=0, unescaped)
                            String[] transParts = new String[]{};
                                Integer[] transCodes = new Integer[]{};
                                    if (isEndsWith || isContains) {
                                        transParts.add('%');
                                        transCodes.add(0);
                                    }
                            for (Integer i=0; i < srcElmt.stringLitParts.size(); i++) {
                                Integer code = srcElmt.stringLitCodes[i];
                                String part = srcElmt.stringLitParts[i];
                                if (code == 0 && part.containsAny('%_')) {
                                    part = part.replace('%', '\\%').replace('_', '\\_');
                                }
                                transParts.add(part);
                                transCodes.add(code);
                            }
                            if (isBeginsWith || isContains) {
                                transParts.add('%');
                                transCodes.add(0);
                            }
                            transElmt.stringLitParts = transParts;
                            transElmt.stringLitCodes = transCodes;
                        } else {
                            // find all '%' or '_' and backslash escape them
                            // tack-on '%' prefix/suffix (unescaped)
                            String coreValue = srcElmt.stringBindValue;
                            if (coreValue.containsAny('%_')) {
                                coreValue = coreValue.replace('%', '\\%').replace('_', '\\_');
                            }
                            if (isEndsWith || isContains) {
                                coreValue = '%' + coreValue;
                            }
                            if (isBeginsWith || isContains && coreValue != '%') {
                                coreValue = coreValue + '%';
                            }
                            // set resolvedStringValue here because we've already escaped it in preparation for the LIKE op serialization:
                            transElmt.resolvedStringValue = transElmt.stringBindValue = coreValue;
                        }
                    } else {
                        // manually serialize the value to a string; note we must also manually manage the simpleExprStack here because the ValueElmt
                        // afterVisit method requires its parent SimpleExpr atop the stack (for type checks):
                        simpleExprStack.add(simpleExpr);
                        try {
                            //simpleExpr.val.traverse(this);
                            srcElmt.traverse(this);
                        } finally {
                            simpleExprStack.remove(simpleExprStack.size() - 1);
                        }
                        if (srcElmt.param != null && srcElmt.paramResolvedValue == null) {
                            serErr(srcElmt.loc, simpleExpr.relOp.lexeme + 
                                    ' operator cannot be applied to unresolved binding parameter [' + srcElmt.ser + ']');
                        } else {
                            serErr(srcElmt.loc, simpleExpr.relOp.lexeme + 
                                    ' operator cannot be applied to non-string value [' + srcElmt.ser + ']');
                        }
                    }
                    
                    // create an alternate "translation" expr that we'll traverse to produce the strict-SOQL LIKE condition:
                    SimpleExpr trans = SimpleExprProto.clone();
                    trans.translatee = simpleExpr;
                    trans.ref = simpleExpr.ref;
                    trans.relOp = simpleExpr.relOp.clone();
                    trans.relOp.ttype = SOQLLexer.KW_LIKE;
                    trans.relOp.injected = true;
                    trans.relOpLexeme = trans.relOp.lexeme = 'LIKE';
                    trans.val = transElmt;
                    trans.traverse(this);
                    simpleExpr.ser = trans.ser;
                    simpleExpr.serLvlOverride = trans.serLvl;
                    // cancel standard traversal since we just did a manual traversal on the val and translation:
                    return false;
                    // translate "between" operator:
                } else if (simpleExpr.relOp != null && simpleExpr.relOp.ttype == SOQLLexer.KW_BETWEEN) {
                    ValueElmt[] elmts = ((ValueList) simpleExpr.val).elements;
                    Boolean[] inclusiveFlags = simpleExpr.valPairInclusiveFlags;
                    CondExpr[] pairExprs = new CondExpr[]{};
                        for (Integer i=0; i < elmts.size(); i += 2) {
                            Integer pairOffset = 0;
                            ValueElmt[] valPair = new ValueElmt[2];
                            do {
                                ValueElmt val = valPair[pairOffset] = elmts[i + pairOffset];
                                if (val.param != null) {
                                    if (val.paramResolvedValue == null) {
                                        // TODO: maybe we should allow unbound param names, or make this behavior a parser setting flag?
                                        serErr(val.param, 'Value parameter :' + val.param.lexeme + ' is unbound');
                                    } else if (val.paramResolvedValue instanceof ValueList) {
                                        serErr(val.param, 'Value parameter :' + val.param.lexeme +
                                                ' is bound to a list; this is not allowed for a between-operator\'s value pair');
                                    }
                                    valPair[pairOffset] = (ValueElmt) val.paramResolvedValue;
                                }
                            } while (++pairOffset < 2);
                            
                            // throws TypeException:
                            ValueElmt[] orderedValPair = heuristicOrderValuePair(valPair[0], valPair[1]);
                            Boolean[] valPairIncFlags;
                            // if we swapped the element order, then we must also swap the inclusive flags order:
                            if (orderedValPair[0] === valPair[0]) {
                                valPairIncFlags = new Boolean[]{ inclusiveFlags[i], inclusiveFlags[i + 1] };
                                    } else {
                                        valPairIncFlags = new Boolean[]{ inclusiveFlags[i + 1], inclusiveFlags[i] };
                                            }
                            
                            SimpleExpr[] bounds = new SimpleExpr[2];
                            pairOffset = 0;
                            do {
                                Integer op;
                                String opLexeme;
                                if (valPairIncFlags[pairOffset]) {
                                    op = pairOffset == 0 ? SOQLLexer.GREATER_THAN_EQUALS : SOQLLexer.LESS_THAN_EQUALS;
                                    opLexeme = pairOffset == 0 ? '>=' : '<=';
                                } else {
                                    op = pairOffset == 0 ? SOQLLexer.GREATER_THAN : SOQLLexer.LESS_THAN;
                                    opLexeme = pairOffset == 0 ? '>' : '<';
                                }
                                SimpleExpr bound = bounds[pairOffset] = SimpleExprProto.clone();
                                bound.translatee = simpleExpr;
                                bound.ref = simpleExpr.ref;
                                bound.relOp = newInjectedToken(op, opLexeme, simpleExpr.relOp);
                                bound.relOpLexeme = opLexeme;
                                bound.val = orderedValPair[pairOffset];
                            } while (++pairOffset < 2);
                            
                            AndExpr pairExpr = AndExprProto.clone();
                            pairExpr.children = new CondExpr[]{ bounds[0], bounds[1] };
                                pairExprs.add(pairExpr);
                        } // for elmts
                    
                    CondExpr trans;
                    if (pairExprs.size() > 1) {
                        OrExpr orExpr = OrExprProto.clone();
                        orExpr.children = pairExprs;
                        trans = orExpr;
                    } else {
                        trans = pairExprs[0];
                    }
                    trans.traverse(this);
                    simpleExpr.ser = trans.ser;
                    simpleExpr.serLvlOverride = trans.serLvl;
                    // cancel standard traversal since we just did a manual traversal on the translation:
                    return false;
                } else {
                    // just-in-time and if necessary (i.e. if simpleExpr.ref.refProc is null, then simpleExpr.ref.fieldTypeToken 
                    // is also guaranteed to be null), run this serializer's ReferenceProcessor instance over simpleExpr.ref:
                    // TODO: should we also check for incompatible baseRefType? (no; let user shoot themselves in foot):
                    if (simpleExpr.ref != null && simpleExpr.ref.refProc == null && refProc.baseRefType != null) {
                        // this call may throw a ReferenceException, depending on this.refProc's settings:
                        refProc.visit(simpleExpr.ref);
                    }
                    // proceed with standard traversal:
                    simpleExprStack.add(simpleExpr);
                    return true;
                }
            }
        }
        
        global virtual override void afterVisit(SimpleExpr simpleExpr) {
            try {
                if (simpleExpr.nested != null) {
                    simpleExpr.ser = simpleExpr.nested.ser;
                    simpleExpr.serLvlOverride = simpleExpr.nested.serLvl;
                } else {
                    String relOpSer = simpleExpr.relOpLexeme.toUpperCase();
                    // a NOT_EQUALS token may be from a '!=' or '<>' lexeme, but we standardize it to '!=':
                    if (simpleExpr.relOp.ttype == SOQLLexer.NOT_EQUALS) {
                        // diamond-op coders HATE him...
                        relOpSer = '!=';
                    }
                    simpleExpr.ser = simpleExpr.ref.ser + ' ' + relOpSer + ' ';
                    String[] valParts;
                    Boolean isValUnresolvedParamName = false;
                    // if this simple expr's ValueElmt is a param binding, then its param may have resolved to a ValueList (in 
                    // simpleExpr.val.paramResolvedValue); in that case this ValueElmt's serParts will have been set to that of
                    // paramResolvedValue.serParts; this is the only case where a ValueElmt instance can have a serParts != null
                    // (ValueList instances should always have serParts != null at this time):
                    if (simpleExpr.val.serParts != null) {                        
                        valParts = simpleExpr.val.serParts;
                        // else this simple expr must be a ValueElmt instance with a single value part (serParts == null):
                    } else {
                        ValueElmt simpleValElmt;
                        if (simpleExpr.val instanceof ValueElmt) {
                            simpleValElmt = (ValueElmt) simpleExpr.val;
                        }
                        if (simpleValElmt != null && simpleValElmt.localReBind != null) {
                            isValUnresolvedParamName = true;
                        } else {
                            isValUnresolvedParamName = simpleValElmt != null && simpleValElmt.paramName != null && simpleValElmt.paramResolvedValue == null;
                        }
                        valParts = new String[]{ simpleExpr.val.ser };
                    }
                    
                    if (valParts.size() == 0) {
                        typeErr(simpleExpr.relOp, 'Value list for ' + simpleExpr.relOpLexeme.toUpperCase() + ' operator cannot be empty');
                    } else if (simpleExpr.isSetOp || simpleExpr.relOp.ttype == SOQLLexer.KW_BETWEEN) {
                        // allow unresolved named-parameter bindings to serialize as the right-hand side of a set op without the wrapping parenthesis -- i.e. avoid
                        // serializing "Foo__c IN (:foo)"; instead we want simply "Foo__c IN :foo":
                        simpleExpr.ser += isValUnresolvedParamName ? valParts[0] : '(' + String.join(valParts, ',') + ')';
                    } else {
                        if (valParts.size() > 1) {
                            typeErr(simpleExpr.relOp, 'Value list cannot be used with ' + simpleExpr.relOpLexeme.toUpperCase() + ' operator');
                        }
                        simpleExpr.ser += valParts[0];
                    }
                    // type checking - if type info is available (i.e. from a preceding ReferenceProcessor traversal), validate it against
                    // the applied condition operator:
                    //Schema.DescribeFieldResult fieldType = simpleExpr.ref.fieldType;
                    Schema.DescribeFieldResult fieldType = simpleExpr.ref.fieldTypeToken?.getDescribe();
                    // fieldType could still be null if it's a polymorphic reference; in that case we ignore it:
                    if (fieldType != null) {
                        // !! in the following TypeExceptions, note the use of originalRelOp; in cases where the current simpleExpr was generated
                        // as part of a translation for an original beginsWith/endsWith/contains-op simple expr, we want to report the error on the
                        // original operator:
                        SOQLLexer.Token[] refChain = simpleExpr.ref.names;
                        Integer opType = simpleExpr.relOp.ttype;
                        // we cannot allow a blob-type field on the left-hand side of a simple expr:
                        // TODO: can equality/inequality ops be used with BLOB fields?
                        if (fieldType.getSOAPType() == Schema.SOAPType.base64binary) {
                            typeErr(simpleExpr.originalRelOp, 'BLOB field ' + simpleExpr.ref.getFullResolvedDescripString() + ' cannot be used in conjunction with the ' +
                                    simpleExpr.originalRelOpLexeme + ' operator');
                        } else if (opType == SOQLLexer.KW_LIKE && fieldType.getSOAPType() != Schema.SOAPType.String) {
                            typeErr(simpleExpr.originalRelOp, 'Field ' + simpleExpr.ref.getFullResolvedDescripString() +
                                    ' is not the String type required by the ' + simpleExpr.originalRelOpLexeme + ' operator');
                        } else if ((opType == SOQLLexer.KW_INCLUDES || opType == SOQLLexer.KW_EXCLUDES)
                                    && fieldType.getType() != Schema.DisplayType.MultiPicklist) {
                                        typeErr(simpleExpr.originalRelOp, 'Field ' + simpleExpr.ref.getFullResolvedDescripString() + ' is not the MultiPicklist type required by the ' +
                                                simpleExpr.originalRelOpLexeme + ' operator');
                                    } else if (relationalOpTypes.contains(opType) && fieldType.getSOAPType() == Schema.SOAPType.Boolean) {
                                        typeErr(simpleExpr.originalRelOp, fieldType.getType().name() + ' field ' + simpleExpr.ref.getFullResolvedDescripString() + ' cannot be used in conjunction with the ' +
                                                simpleExpr.originalRelOpLexeme + ' operator');
                                    }
                    }
                }
            } finally {
                // this is in a finally block because we MUST cleanup the stack:
                simpleExprStack.remove(simpleExprStack.size() - 1);
            }
        }
        
        global virtual override void afterVisit(RefExpr refExpr) {
            refExpr.ser = refExpr.refHead != null ? refExpr.refHead.getFullResolvedString() : refExpr.toString();
        }
        
        global virtual override Boolean visit(ValueList valueList) {
            valueList.serParts = new String[]{};
                return true;
        }
        
        global virtual override void afterVisit(ValueList valueList) {
            for (Value v : valueList.elements) {
                if (v instanceof ValueList) {
                    valueList.serParts.addAll(((ValueList) v).serParts);
                } else {
                    valueList.serParts.add(v.ser);
                }
            }
        }
        
        global virtual override void afterVisit(ValueElmt v) {
            v.serParts = null;
            if (v.localReBind != null) {
                v.ser = ':' + v.localReBind.getLocalVar();
            } else if (v.param != null) {
                if (v.paramResolvedValue != null) {
                    //System.assert(false, v.paramResolvedValue);
                    // TODO: make a SOQLParser setting whereby named params output to SOQL are not allowed; for now we always allow it:
                    v.ser = v.paramResolvedValue.ser;
                    v.serParts = v.paramResolvedValue.serParts;
                } else if (v.paramName != null) {
                    v.ser = ':' + v.paramName.lexeme;
                } else if (v.paramIndex != null) {
                    //v.ser = ':' + v.paramIndex.lexeme;
                    serErr(v.param, 'Indexed parameter :' + v.paramIndex.lexeme + ' cannot be output to SOQL');
                    // !! this branch should be unreachable because anonymous params must be bound at time of parse:
                } else if (v.paramAnon != null) {
                    //v.ser = '?';
                    serErr(v.param, 'Anonymous parameter cannot be output to SOQL');
                }
            } else {
                if (v.kwLit != null) {
                    v.ser = v.kwLit.lexeme.toLowerCase();
                    SimpleExpr simpleExpr = simpleExprStack[simpleExprStack.size() - 1];
                    Integer op = simpleExpr.relOp.ttype;
                    if (v.kwLit.ttype == SOQLLexer.KW_TRUE || v.kwLit.ttype == SOQLLexer.KW_FALSE) {
                        // System.assert(false, v.kwLit);
                        matchType(v, Schema.SOAPType.Boolean, 'Boolean');
                        // boolean value cannot be right-hand side of a relational op:
                        if (op == SOQLLexer.KW_BETWEEN || relationalOpTypes.contains(op)) {
                            typeErr(simpleExpr.originalRelOp, simpleExpr.originalRelOpLexeme + ' operator cannot accept a Boolean right-hand side value');
                        }
                    // null value cannot be right-hand side of a contains/beginsWith/endsWith/between or a LIKE or a relational op:
                    } else if (v.kwLit.ttype == SOQLLexer.KW_NULL) {
                        if (op == SOQLLexer.KW_CONTAINS || op == SOQLLexer.KW_BEGINS_WITH || op == SOQLLexer.KW_STARTS_WITH || op == SOQLLexer.KW_ENDS_WITH
                                || op == SOQLLexer.KW_BETWEEN || op == SOQLLexer.KW_LIKE || relationalOpTypes.contains(op)) {
                            typeErr(simpleExpr.originalRelOp, simpleExpr.originalRelOpLexeme + ' operator cannot accept a null right-hand side value');
                        }
                    }
                } else if (v.numberLit != null) {
                    v.ser = v.numberLit.toPlainString();
                    matchType(v, Schema.SOAPType.Integer, Schema.SOAPType.Double, 'Number');
                } else if (v.specialNumberLit != null) {
                    typeErr(v.loc, 'Number value ' + v.specialNumberLit + ' cannot be represented in SOQL');
                } else if (v.dateTimeLit != null) {
                    String secs = ('00' + v.dateTimeLit.secondGmt()).right(2) + '.' + ('000' + v.dateTimeLit.millisecondGmt()).right(3);
                    //Decimal secs = v.dateTimeLit.secondGmt() + v.dateTimeLit.millisecondGmt() / 1000.0;
                    // note that secs may be a decimal, which is allowed in SOQL syntax:
                    v.ser = v.dateTimeLit.formatGmt('yyyy-MM-dd') + 'T' + v.dateTimeLit.formatGmt('HH:mm') + ':' + secs + 'Z'; /*(secs == 0 ? '00' : '' + secs.toPlainString()) + 'Z'*/
                    matchType(v, Schema.SOAPType.Date, Schema.SOAPType.DateTime, 'DateTime');
                } else if (v.dateLit != null) {
                    v.ser = DateTime.newInstanceGMT(v.dateLit.year(), v.dateLit.month(), v.dateLit.day(), 0, 0, 0).formatGMT('yyyy-MM-dd');
                    matchType(v, Schema.SOAPType.Date, Schema.SOAPType.DateTime, 'Date');
                } else if (v.dateFormula != null) {
                    v.ser = v.dateFormula.lexeme.toUpperCase();
                    if (v.dateFormula_N != null) {
                        v.ser += ':' + v.dateFormula_N;
                    }
                    matchType(v, Schema.SOAPType.Date, Schema.SOAPType.DateTime, 'Date Formula');
                } else if (v.isString == true) {
                    // find the closest parent simple expr that has a req/eq operator:
                    SimpleExpr relEqExpr; // = closestRelEqExpr();
                    Integer len = simpleExprStack.size();
                    for (Integer i=len - 1; i >= 0; i--) {
                        SimpleExpr simp = simpleExprStack[i];
                        if (simp.relOp != null) {
                            relEqExpr = simp;
                            break;
                        }
                    }
                    // if this value isn't the target of a LIKE op, then any '\%' or '\_' escape sequences should be reduced to '%' and
                    // '_' respectively:
                    if (relEqExpr == null || relEqExpr.relOp == null || relEqExpr.relOp.ttype != SOQLLexer.KW_LIKE) {
                        // since this is not the target of a like, backslashed '%' and '_' will be reduced to plain '%' and '_' respectively:
                        v.ser = v.getStringSer(false);
                    } else {
                        // since this is the target of a like, backslashed '%' and '_' will retain their backslashes:
                        v.ser = v.getStringSer(true);
                    }
                    matchType(v, Schema.SOAPType.String, Schema.SOAPType.Id, 'String');
                }
            }
        }
        
        void matchType(ValueElmt v, Schema.SOAPType acceptedType, String rhsTypeDescrip) {
            matchType(v, new Schema.SOAPType[]{ acceptedType }, rhsTypeDescrip);
        }
        
        void matchType(ValueElmt v, Schema.SOAPType acceptedType1, Schema.SOAPType acceptedType2, String rhsTypeDescrip) {
            matchType(v, new Schema.SOAPType[]{ acceptedType1, acceptedType2 }, rhsTypeDescrip);
        }
        
        // this method should be called AFTER v.ser is set:
        void matchType(ValueElmt v, Schema.SOAPType[] acceptedTypes, String rhsTypeDescrip) {
            // get the closest simple expr parent to this value:
            SimpleExpr simpleExpr = simpleExprStack[simpleExprStack.size() - 1];
            // if simpleExpr.ref.fieldType has been resolved (i.e. via a preceding traversal of ReferenceProcessor), then continue
            // to validate the left-hand side vs. right-hand side types; if not resolved then return:
            //Schema.DescribeFieldResult fieldType = simpleExpr.ref.fieldType;
            Schema.DescribeFieldResult fieldType = simpleExpr.ref.fieldTypeToken?.getDescribe();
            if (fieldType == null) {
                return;
            }
            // field type will have been resolved above, but it may still be left null if it was a polymorphic reference;
            // in that case bypass these type checks:
            Schema.SOAPType sType = fieldType.getSOAPType();
            Boolean match = false;
            for (Schema.SOAPType aType : acceptedTypes) {
                if (sType == aType) {
                    match = true;
                    break;
                }
            }
            if (!match) {
                typeErr(v.loc, 'sObject field ' + simpleExpr.ref.getFullResolvedDescripString() + 
                        ' expected a right-hand side ' + sType.name() + ' value; got a ' + rhsTypeDescrip + ' ' + v.ser);
            }
        }
    }
    
    // Expression levels; smaller numbers indicate "higher" nodes in the parse tree. A "raise" is a move from a larger lvl# to a smaller lvl#:
    private static final Integer LVL_OR     = 0;
    private static final Integer LVL_AND    = 1;
    private static final Integer LVL_NOT    = 2;
    private static final Integer LVL_SIMPLE = 3;
    private static final Integer LVL_REF    = 4;
    
    // Parser loop actions:
    private static final Integer NEW_PART   = 0;
    private static final Integer MERGE_PART = 1;
    // NO_OP is a special action that allows a next iteration of the parting loop to bypass the NEW/EXTEND/MERGE_PART actions and proceed
    // directly to the next operator token and next action dispatch -- this is used after completeing the raise from a relational/equality
    // op and parsing the right-hand side value(s) to complete a SimpleExpr:
    private static final Integer NO_OP      = 2;
    // Merge return action types:
    private static final Integer PARSE_FINISHED     = 0;
    private static final Integer MERGE_LOG_BIN_TERM = 1; // i.e. merge rhs term for AndExpr or OrExpr
    private static final Integer MERGE_NOT          = 2;
    private static final Integer MERGE_NESTED       = 3;
    
    // Bottom-up parsing loop:
    public static CondExpr parseCondExpr(SOQLParser parser, String stringInput, Integer maxLvl) {
        if (String.isBlank(stringInput)) {
            AndExpr emptyExpr = AndExprProto.clone();
            emptyExpr.parser = parser;
            emptyExpr.isTopParsed = true;
            emptyExpr.children = new CondExpr[]{};
                return emptyExpr;
        }
        return parseCondExpr(parser, SOQLLexer.newLexer(stringInput), maxLvl, true);
    }

    // Bottom-up parsing loop:
    private static CondExpr parseCondExpr(SOQLParser parser, SOQLLexer lex, Integer maxLvl, Boolean matchEOF) {
        SOQLLexer.Token[] toks = lex.toks;
        ExprPart[] parts = new ExprPart[]{}; // the stack of expresison parts awaiting completion
            ExprPart part; // the current part
        Integer action = NEW_PART;
        ExprPart newPart;
        Integer newPartMaxLvl = maxLvl;
        Integer newPartMergeType = PARSE_FINISHED;
        SOQLLexer.Token tok, peek, opTok;
        String opTokLexeme;
        
        do {
            if (action == NEW_PART) {
                // Consume next token, which is the 1st token in the new expression part:
                tok = toks[lex.next++];
                // Handle a unary prefix NOT operator:
                SOQLLexer.Token unaryNot;
                // TODO: should we allow chained NOT ops? chained NOTs are obviously redundant, but not necessarily syntactically invalid...
                if (tok.ttype == SOQLLexer.KW_NOT || tok.ttype == SOQLLexer.LOGICAL_NOT) {
                    unaryNot = tok;
                    // Error if a unary NOT raises this new part beyond its max allowed level:
                    if (newPartMaxLvl > LVL_NOT) {
                        // parse error; NOT isn't allowed here:
                        // TODO: look at top part for more specific error, e.g. MathExpr
                        // TODO: this error may not be reachable in current grammar and parser impl...
                        parseErr(tok, 'NOT operator isn\'t allowed here');
                    }
                    // Consume the next token for inspection by subsequent logic; error if it's a chained NOT:
                    tok = toks[lex.next++];
                    if (tok.ttype == SOQLLexer.KW_NOT || tok.ttype == SOQLLexer.LOGICAL_NOT) {
                        // parse error; unary NOT ops can't be chained:
                        parseErr(tok, 'Chained NOT operators aren\'t allowed');
                    }
                    // mint a new NotExpr, add it to the expr parts stack, and modify params for the additional new part that will come after it:
                    newPart = NotExprProto.clone();
                    newPart.maxLvl = newPartMaxLvl;
                    newPart.mergeType = newPartMergeType;
                    parts.add(newPart);
                    // after the newling minted NotExpr, we must start a new part with a max lvl 1 below that of NotExpr:
                    newPartMaxLvl = LVL_NOT + 1;
                    newPartMergeType = MERGE_NOT;
                }
                
                // if we're looking at a NAME token (note that we also allow keyword tokens to be used as names) then start a RefExpr:
                if (tok.ttype == SOQLLexer.NAME || tok.ttype >= SOQLLexer.KEYWORD_MINIMUM) {
                    if (unaryNot != null && unaryNot.ttype == SOQLLexer.LOGICAL_NOT) {
                        parseErr(unaryNot, 'Unary "!" operator cannot be applied directly to a sub-condition; use the NOT keyword or wrap the sub-condition in parenthesis');
                    }
                    RefExpr ref = RefExprProto.clone();
                    parts.add(part = ref);
                    ref.maxLvl = newPartMaxLvl;
                    ref.mergeType = newPartMergeType;
                    ref.names = new SOQLLexer.Token[]{ tok };
                        // peek for a DOT op, which will continue the ref expr:
                        while (toks[lex.next].ttype == SOQLLexer.DOT) {
                            lex.next++; // consume DOT
                            tok = toks[lex.next++]; // here we expect a NAME; consume it
                            if (tok.ttype != SOQLLexer.NAME && tok.ttype < SOQLLexer.KEYWORD_MINIMUM) {
                                // parse error; NAME expected to follow a DOT operator:
                                mismatch(tok, 'Expected identifier name to follow dot-operator in compound field reference');
                            }
                            ref.names.add(tok);
                        }
                    // If OPEN_PAREN, then create both a SimpleExpr and then a full nested expression that shall merge back into the SimpleExpr's "nested" property:
                } else if (tok.ttype == SOQLLexer.OPEN_PAREN) {
                    newPart = SimpleExprProto.clone();
                    ((SimpleExpr) newPart).nestedStart = tok;
                    newPart.maxLvl = newPartMaxLvl;
                    newPart.mergeType = newPartMergeType;
                    // note that we don't need to update the current/top part variable "part" because we're just going to continue back to NEW_PART again:
                    parts.add(newPart);
                    action = NEW_PART;
                    // nesting parenthesis can contain the highest-level expressions (i.e. lvl=0, OrExpr):
                    newPartMaxLvl = 0;
                    newPartMergeType = MERGE_NESTED;
                    continue;
                } else {
                    // parse error; expected NAME or nested expression condition
                    if (part == null && newPartMergeType != MERGE_NOT) {
                        //mismatch(tok, 'Expected a starting condition');
                        mismatch(tok, 'Expected a condition');
                    } else {
                        // since NOT isn't an infix operator, we must first check newPart to see if it's starting a NotExpr; if so
                        // then use that as the context/incomplete expr type:
                        if (newPartMergeType == MERGE_NOT) {
                            mismatch(tok, 'Expected a condition to follow NOT operator');
                        } else if (part.lvl == LVL_OR) {
                            mismatch(tok, 'Expected a condition to follow OR operator');
                        } else if (part.lvl == LVL_AND) {
                            mismatch(tok, 'Expected a condition to follow AND operator');
                        } else if (part.lvl == LVL_NOT) {
                            mismatch(tok, 'Expected a sub-condition to follow NOT operator');
                            // TODO: the following branch should not be reachable:
                        } else {
                            //mismatch(tok, 'Expected a field reference or nested condition');
                            mismatch(tok, 'Expected a field or grouped condition');
                        }
                    }
                }
                
                // if we come around to a merge, we're guaranteed that opTok and opTokLexeme will be populated to the operator that instigated this merge:
            } else if (action == MERGE_PART) {
                Integer newTop = parts.size() - 2;
                ExprPart rhsPart = parts.remove(newTop + 1);
                // after this merge, the left-hand side part will become the new current/top part:
                ExprPart lhsPart = part = newTop >= 0 ? parts[newTop] : null;
                
                // for every type of merge, the right-hand side part must be a complete condition -- i.e. it must be an instanceof CondExpr and must
                // have a lvl at or above SimpleExpr (i.e. rhsPart.lvl <= 3):
                if (rhsPart.lvl > LVL_SIMPLE) {
                    // parse error; expected relational or equality op to complete the condition; got unexpected operator
                    //mismatch(opTok, 'Expected field operator to follow field expression');
                    String fieldPathStr = rhsPart.toString(); // rhsPart is expected to be an instance of RefExpr
                    mismatch(opTok, 'Expected an operator to follow field ' + fieldPathStr);
                    //mismatch(opTok, 'Expected a comparison operator to act on field reference ' + fieldPathStr);
                }
                
                if (rhsPart.mergeType == MERGE_LOG_BIN_TERM) {
                    ((NestExpr) lhsPart).children.add((CondExpr) rhsPart);
                } else if (rhsPart.mergeType == MERGE_NESTED) {
                    ((SimpleExpr) lhsPart).nested = (CondExpr) rhsPart;
                    // and match a terminating ')' token to finish up the nested expression:
                    tok = toks[lex.next++];
                    if (tok.ttype != SOQLLexer.CLOSE_PAREN) {
                        //mismatch(tok, 'Expected \')\' to close nested expression');
                        mismatch(tok, 'Expected matching right parenthesis', 
                                 new SOQLLexer.Token[]{ ((SimpleExpr) lhsPart).nestedStart });
                    }
                } else if (rhsPart.mergeType == MERGE_NOT) {
                    ((NotExpr) lhsPart).operand = (CondExpr) rhsPart;
                } else if (rhsPart.mergeType == PARSE_FINISHED) {
                    // when the parse is finished we must not have leftover tokens
                    // TODO: make this check a configurable parse setting...
                    if (opTok.ttype != SOQLLexer.EOF && matchEOF == true) {
                        // parse error; unexpected token when expected EOF
                        //mismatch(opTok, 'Unexpected end of condition expression');
                        if (opTok.ttype == SOQLLexer.ERROR) {
                            //mismatch(opTok, 'Unexpected error after whole condition');
                            mismatch(opTok, 'Dangling characters following condition');
                        } else {
                            //mismatch(opTok, 'Unexpected continuation after whole condition');
                            mismatch(opTok, 'Dangling tokens following condition');
                        }
                    }
                    CondExpr topPart = (CondExpr) rhsPart;
                    topPart.isTopParsed = true;
                    topPart.parser = parser;
                    return topPart;
                }
                
                if (rhsPart.lvl <= LVL_SIMPLE && parts[0].lvl <= LVL_SIMPLE) {
                    CondExpr rhsCond = (CondExpr) rhsPart;
                    rhsCond.parsedTop = (CondExpr) parts[0];
                    rhsCond.parser = parser;
                }
            }
            
            // next action dispatch, including raise logic:
            
            // peek at the next token (don't consume it yet) to determine the next action from its op lvl:
            opTok = toks[lex.next];
            opTokLexeme = opTok.lexeme;
            Integer raiseLvl = SOQLLexer.ExprLevelTable[opTok.ttype];
            // the NOT operator is a special case -- if the current expr part is a RefExpr, and we're looking at a NOT token followed by a subsequent IN token,
            // then we're looking at the "NOT IN" relational op rather than the logical NOT operator; if NOT IN then we must make some modifications:
            if (opTok.ttype == SOQLLexer.KW_NOT && part.lvl >= LVL_REF && toks[lex.next + 1].ttype == SOQLLexer.KW_IN) {
                // adjust the lvl for NOT IN:
                raiseLvl = LVL_SIMPLE;
                opTokLexeme += ' ' + toks[lex.next + 1].lexeme;
                // the NOT IN can't possible cause a merge (since there are no math expressions in SOQL anymore), so consume the NOT IN tokens and
                // fallthrough to the raise/extend logic:
                lex.next += 2;
                // if not a NOT IN then we don't need to adjust lvl; simply check for a merge:
            } else if (raiseLvl < part.maxLvl) {
                action = MERGE_PART;
                continue;
                // if not a NOT IN and not a merge then is must be an op token that evokes a raise and/or extend (or an invalid lower); now we consume the op token:
            } else {
                lex.next++;
            }
            
            if (raiseLvl < part.lvl) {
                // OR and AND accept raises from any lvl at or above SIMPLE:
                if (raiseLvl <= LVL_AND) {
                    if (part.lvl <= LVL_SIMPLE) {
                        NestExpr nestPart;
                        if (raiseLvl == LVL_OR) {
                            nestPart = OrExprProto.clone();
                            // else we must be raising to LVL_AND:
                        } else {
                            nestPart = AndExprProto.clone();
                        }
                        // we know that part must be an instanceof CondExpr because it's at or above LVL_SIMPLE:
                        nestPart.children = new CondExpr[]{ (CondExpr) part };
                            nestPart.maxLvl = part.maxLvl;
                        nestPart.mergeType = part.mergeType;
                        // replace the current/top part with the newly wrapped part:
                        parts[parts.size() - 1] = part = nestPart;
                        // fallthrough to EXTEND...
                    } else {
                        // TODO: this branch shouldn't be reachable...
                        // parse error; invalid raise operation (e.g. AND in place of a relational/equality op)
                        parseErr(opTok, opTokLexeme.toUpperCase() + ' operator isn\'t allowed here');
                    }
                    // note that the NOT token isn't assigned an op level, so we need not check for that here...
                    // else it must be a raise to LVL_SIMPLE (i.e. via relational/equality op, not a nested simple part):
                } else {
                    SimpleExpr relPart = SimpleExprProto.clone();
                    relPart.maxLvl = part.maxLvl;
                    relPart.mergeType = part.mergeType;
                    relPart.ref = (RefExpr) part;
                    relPart.relOp = opTok;
                    relPart.relOpLexeme = opTokLexeme; // this is used to help distinguish the 2-token NOT IN op
                    parts[parts.size() - 1] = part = relPart;
                    
                    // parse the value(s):
                    Boolean isSetOp = opTok.ttype == SOQLLexer.KW_NOT || opTok.ttype == SOQLLexer.KW_IN || opTok.ttype == SOQLLexer.KW_INCLUDES
                        || opTok.ttype == SOQLLexer.KW_EXCLUDES;
                    Boolean parseList = isSetOp;
                    Boolean parsePair = opTok.ttype == SOQLLexer.KW_BETWEEN;
                    Boolean parseListOfPairs;
                    // peek at next token:
                    peek = toks[lex.next];
                    // we allow a parameterized value in place of a list literal:
                    if (peek.ttype == SOQLLexer.COLON || peek.ttype == SOQLLexer.QUEST_MARK) {
                        parseList = false;
                    }
                    
                    String valuePosDescrip = 'following ' + opTokLexeme.toUpperCase() + ' operator';
                    Integer valuePosIndex = 1;
                    Integer valuePairIndex;
                    ValueList valueList;
                    ValueElmt valueElmt;
                    Boolean[] pairInclusiveFlags;
                    
                    if (parsePair) {
                        pairInclusiveFlags = new Boolean[]{};
                            valuePairIndex = 0;
                        Boolean leadsWithParen = false;
                        if ((leadsWithParen = peek.ttype == SOQLLexer.OPEN_PAREN) || peek.ttype == SOQLLexer.OPEN_BRACKET) {
                            SOQLLexer.Token peek2 = toks[lex.next + 1];
                            if (peek2.ttype == SOQLLexer.OPEN_PAREN || peek2.ttype == SOQLLexer.OPEN_BRACKET) {
                                if (!leadsWithParen) {
                                    parseErr(peek2, 'Value-pair cannot be nested inside of a bracket');
                                }
                                lex.next++;
                                parseListOfPairs = true;
                            } else if (peek2.ttype == SOQLLexer.COMMA) {
                                // parse error; value list cannot start with a comma
                                parseErr(peek2, 'Value-pair cannot start with a leading comma');
                            } else {
                                parseListOfPairs = false;
                            }
                        } else if (peek.ttype == SOQLLexer.COLON || peek.ttype == SOQLLexer.QUEST_MARK) {
                            // parse error; expected value pair or ist of pairs
                            mismatch(peek, 'The between operator expects an explicit value-pair or a list of value-pairs; dynamic binding is not allowed');
                        } else {
                            mismatch(peek, 'The between operator expects an explicit value-pair or a list of value-pairs');
                        }
                        relPart.valPairInclusiveFlags = new Boolean[]{};
                            relPart.val = valueList = new ValueList();
                        valueList.elements = new ValueElmt[]{};
                            } else if (parseList) {
                                // match a '(' token to start the list:
                                if (peek.ttype == SOQLLexer.OPEN_PAREN) {
                                    // consume the '(' and then peek at the next token to ensure it isn't a leading COMMA:
                                    lex.next++;
                                    peek = toks[lex.next];
                                    if (peek.ttype == SOQLLexer.COMMA) {
                                        // parse error; value list cannot start with a comma
                                        parseErr(peek, 'Value list cannot start with a leading comma');
                                    }
                                } else if (peek.ttype != SOQLLexer.COLON && peek.ttype != SOQLLexer.QUEST_MARK) {
                                    // parse error; expected list of values or parameter
                                    mismatch(peek, 'Expected start of a value list expression ' + valuePosDescrip);
                                }
                                valueElmt = new ValueElmt();
                                relPart.val = valueList = new ValueList();
                                valueList.elements = new ValueElmt[]{ valueElmt };
                                    valuePosDescrip = 'at position #' + valuePosIndex + ' in value list';
                            } else {
                                relPart.val = valueElmt = new ValueElmt();
                            }
                    
                    // the following loop parses 1 or more value-pairs:
                    do {
                        if (parsePair) {
                            tok = toks[lex.next++];
                            if (tok.ttype == SOQLLexer.OPEN_PAREN) {
                                relPart.valPairInclusiveFlags.add(false);
                            } else if (tok.ttype == SOQLLexer.OPEN_BRACKET) {
                                relPart.valPairInclusiveFlags.add(true);
                            } else {
                                // parse error; expected start of value-pair
                                mismatch(tok, 'Expected \'(\' or \'[\' to start a value-pair');
                            }
                            valueElmt = new ValueElmt();
                            valueList.elements.add(valueElmt);
                            valuePairIndex++;
                            valuePosIndex = 1;
                            valuePosDescrip = 'at left-hand side of value-pair #' + valuePairIndex;
                        }
                        
                        // the following loop parses 1 or more value elements:
                        do {
                            // TODO: need to add handling of currency literals !!
                            
                            // consume the 1st token of this next value element:
                            tok = toks[lex.next++];
                            valueElmt.loc = tok;
                            if (tok.ttype == SOQLLexer.COLON) {
                                tok = toks[lex.next++];
                                if (tok.ttype == SOQLLexer.NAME || tok.ttype >= SOQLLexer.KEYWORD_MINIMUM) {
                                    valueElmt.paramName = valueElmt.param = tok;
                                } else if (tok.ttype == SOQLLexer.DECIMAL_NUMBER) {
                                    ((CondExpr) parts[0]).hasIndexedParam = true;
                                    Boolean invalidInt = tok.lexeme.contains('.');
                                    if (!invalidInt) {
                                        Integer intVal;
                                        try {
                                            intVal = Integer.valueOf(tok.lexeme);
                                        } catch (Exception e) {
                                            invalidInt = true;
                                        } finally {
                                            if (!invalidInt) {
                                                if (intVal >= (1 << 15)) {
                                                    invalidInt = true;
                                                } else {
                                                    valueElmt.paramIndex = valueElmt.param = tok;
                                                    valueElmt.paramIndexIntVal = intVal;
                                                }
                                            }
                                        }
                                    }
                                    if (invalidInt) {
                                        mismatch(tok, 'Field value ' + valuePosDescrip + ' expected parameter index to be a small integer value');
                                    }
                                } else {
                                    // parse error; expected parameter name or index after colon
                                    mismatch(tok, 'Field value ' + valuePosDescrip + ' expected a parameter name or integer index to follow the colon');
                                }
                            } else if (tok.ttype == SOQLLexer.QUEST_MARK) {
                                // anonymous positioned parameter:
                                valueElmt.paramAnon = valueElmt.param = tok;
                                ((CondExpr) parts[0]).anonParamCount++;
                            } else if (tok.ttype == SOQLLexer.STRING_LITERAL) {
                                valueElmt.isString = true;
                                valueElmt.stringLitParts = tok.stringLitParts;
                                valueElmt.stringLitCodes = tok.stringLitCodes;
                            } else if (tok.ttype == SOQLLexer.DECIMAL_NUMBER) {
                                peek = toks[lex.next];
                                // if this number is an integer with 4 digits and the next token is a '-' then we might be looking at a date or datetime:
                                if (peek.ttype == SOQLLexer.MINUS && !peek.hasLeadBoundary && tok.lexeme.length() == 4
                                    && !tok.lexeme.contains('.')) {
                                        SOQLLexer.Token peek2 = toks[lex.next + 1];
                                        // if we see a month component (an integer with 1 or 2 digits; this timw we allow a whitespace boundary) then we assume we're looking
                                        // at a date or datetime:
                                        if (peek2.ttype == SOQLLexer.DECIMAL_NUMBER && peek2.lexeme.length() <= 2
                                            && !peek2.lexeme.contains('.')) {
                                                lex.next += 2;
                                                matchDateLiteral(lex, valueElmt, tok, peek2);
                                            } else {
                                                valueElmt.numberLit = Decimal.valueOf(tok.lexeme);
                                            }
                                    } else {
                                        valueElmt.numberLit = Decimal.valueOf(tok.lexeme);
                                    }
                            } else if (tok.ttype == SOQLLexer.KW_NULL || tok.ttype == SOQLLexer.KW_FALSE || tok.ttype == SOQLLexer.KW_TRUE) {
                                valueElmt.kwLit = tok;
                            } else if (tok.ttype >= SOQLLexer.DATE_FORMULA_KEYWORD_MINIMUM) {
                                matchDateFormula(lex, valueElmt, tok);
                            } else {
                                // parse error; expected value token type (e.g. STRING_LITERAL); got unexpected token
                                mismatch(tok, 'Expected field value ' + valuePosDescrip);
                            }
                            
                            if (parsePair) {
                                // for a value-pair we expect a ',' or ']' or ')' to follow each value element; consume the next token:
                                tok = toks[lex.next++];
                                if (tok.ttype == SOQLLexer.COMMA) {
                                    // allow for a trailing comma; if we see a ']' or ')' following a comma then we consume it and break
                                    // this parse-values loop:
                                    peek = toks[lex.next];
                                    if (peek.ttype == SOQLLexer.CLOSE_PAREN || peek.ttype == SOQLLexer.CLOSE_BRACKET) {
                                        // consume the close paren/bracket token:
                                        tok = toks[lex.next++];
                                        // fallthrough to subsequent close-pair processing...
                                    } else if (peek.ttype == SOQLLexer.COMMA) {
                                        // parse error; consecutive commas are not allowed in value lists
                                        parseErr(peek, 'Consecutive commas in value list are not allowed');
                                    } else {
                                        // if we got a non-trailing comma then continue to parse the next value element:
                                        valueElmt = new ValueElmt();
                                        valueList.elements.add(valueElmt);
                                        valuePosIndex++;
                                        if (valuePosIndex > 2) {
                                            parseErr(peek, 'Value-pair must have exactly 2 value elements; got ' + valuePosIndex);
                                        }
                                        valuePosDescrip = 'at ' + (valuePosIndex == 1 ? 'left-hand side' : 'right-hand side') + ' of value-pair #' + valuePairIndex;
                                        continue;
                                    }
                                }
                                if (tok.ttype == SOQLLexer.CLOSE_BRACKET || tok.ttype == SOQLLexer.CLOSE_PAREN) {
                                    if (valuePosIndex < 2) {
                                        parseErr(tok, 'Value-pair must have exactly 2 value elements; got ' + valuePosIndex);
                                    }
                                    relPart.valPairInclusiveFlags.add(tok.ttype == SOQLLexer.CLOSE_BRACKET);
                                    break;
                                } else {
                                    mismatch(tok, 'Expected \',\' or \']\' or \')\' to continue or terminate value-pair');
                                }
                            } else if (parseList) {
                                // for a value list we expect a ',' or ')' to follow each value element; consume the next token:
                                tok = toks[lex.next++];
                                if (tok.ttype == SOQLLexer.COMMA) {
                                    // allow for a trailing comma; if we see a ')' following a comma then we consume the ')' and break
                                    // this parse-values loop:
                                    peek = toks[lex.next];
                                    if (peek.ttype == SOQLLexer.CLOSE_PAREN) {
                                        lex.next++;
                                        break;
                                    } else if (peek.ttype == SOQLLexer.COMMA) {
                                        // parse error; consecutive commas are not allowed in value lists
                                        parseErr(peek, 'Consecutive commas in value list are not allowed');
                                    }
                                    // if we got a non-trailing comma then continue to parse the next value element:
                                    valueElmt = new ValueElmt();
                                    valueList.elements.add(valueElmt);
                                    valuePosIndex++;
                                    valuePosDescrip = 'at position #' + valuePosIndex + ' in value list';
                                    continue;
                                } else if (tok.ttype == SOQLLexer.CLOSE_PAREN) {
                                    break;
                                } else {
                                    mismatch(peek, 'Expected \',\' or \')\' to continue or terminate value list');
                                }
                            } else {
                                break;
                            }
                        } while (true); // value list loop
                        
                        if (parseListOfPairs == true) {
                            // for a list of value-pairs we expect a ',' or ')' to follow each value-pair; consume the next token:
                            tok = toks[lex.next++];
                            if (tok.ttype == SOQLLexer.COMMA) {
                                // allow for a trailing comma; if we see a ')' following a comma then we consume the ')' and break
                                // this parse-value-pair list loop:
                                peek = toks[lex.next];
                                if (peek.ttype == SOQLLexer.CLOSE_PAREN) {
                                    lex.next++;
                                    break;
                                } else if (peek.ttype == SOQLLexer.COMMA) {
                                    // parse error; consecutive commas are not allowed in value-pairs lists
                                    parseErr(peek, 'Consecutive commas in value-pairs list are not allowed');
                                }
                                // if we got a non-trailing comma then continue to parse the next value-pair:
                                valuePosIndex = 1;
                                valuePairIndex++;
                                valuePosDescrip = 'at left-hand side of value-pair #' + valuePairIndex;
                                continue;
                            } else if (tok.ttype == SOQLLexer.CLOSE_PAREN) {
                                break;
                            } else {
                                mismatch(tok, 'Expected \',\' or \')\' to continue or terminate value-pairs list');
                            }
                        } else {
                            break;
                        }
                        
                    } while (true); // value-pairs list loop
                    
                    // now that we've completed parsing a relational/equality expression, the next action after should be to bypass the NEXT/EXTEND/MERGE_PART actions and
                    // fallthrough directly to the raise/merge logic section again:
                    action = NO_OP;
                    continue;
                }
            } else if (raiseLvl > part.lvl) {
                // parse error; invalid/unexpected token (i.e. "lower")
                // TODO: can this actually happen in this grammar?
                parseErr(opTok, opTokLexeme.toUpperCase() + ' operator isn\'t allowed here');
            }
            
            // If we fell-through to here then enact an EXTEND; note that in SOQL expression syntax only OrExpr, and AndExpr parts can be extended:
            //action = EXTEND_PART;
            
            // extend an OrExpr or an AndExpr:
            if (part.lvl <= LVL_AND) {
                action = NEW_PART;
                newPartMaxLvl = part.lvl + 1;
                newPartMergeType = MERGE_LOG_BIN_TERM;
            } else {
                // TODO: this should be unreachable; it's only used for now to catch bugs in the parsing logic:
                System.assert(false, 'Unexpected extension on a part of lvl ' + part.lvl + ' via operator ' + opTokLexeme + loc(opTok));
            }
            
            // you're not a cool kid unless you regularly code do-while-true loops:
        } while (true);
        
        // Unreachable:
        return null;
    }
    
    public static void parseErr(SOQLLexer.Token loc, String errMsg) {
        //err(loc, new ParseException(errMsg + loc(loc)));
        parseErr(loc, errMsg, 0, null);
    }
    
    public static void mismatch(SOQLLexer.Token badTok, String errMsg) {
        parseErr(badTok, errMsg, 1, null);
    }
    
    public static void mismatch(SOQLLexer.Token badTok, String errMsg, SOQLLexer.Token[] addlHighlights) {
        parseErr(badTok, errMsg, 1, addlHighlights);
    }
    
    public static void parseErr(SOQLLexer.Token badTok, String errMsg, Integer showBadTok, SOQLLexer.Token[] addlHighlights) {
        String msg = errMsg;
        if (showBadTok != null && showBadTok > 0) {
            if (badTok.ttype == SOQLLexer.STRING_LITERAL) {
                msg += '; got string constant' + (badTok.lexeme.length() < 40 ? ' ' + badTok.lexeme : '');
            } else if (badTok.ttype == SOQLLexer.DECIMAL_NUMBER) {
                msg += '; got number constant ' + badTok.lexeme;
            } else if (badTok.ttype == SOQLLexer.NAME) {
                msg += '; got identifier name ' + badTok.lexeme;
            } else if (badTok.ttype >= SOQLLexer.KEYWORD_MINIMUM) {
                msg += '; got keyword ' + badTok.lexeme;
            } else if (badTok.ttype >= SOQLLexer.PLUS) {
                msg += '; got operator ' + badTok.lexeme;
            } else if (badTok.ttype >= SOQLLexer.COMMA) {
                msg += '; got punctuator ' + badTok.lexeme;
            } else if (badTok.ttype == SOQLLexer.ERROR) {
                msg += '; encountered ' + badTok.errorMsg;
            } else if (badTok.ttype == SOQLLexer.EOF) {
                msg += '; encountered unexpected end of input';
                // TODO: unreachable...
            } else {
                msg += badTok.lexeme;
            }
        }
        msg += loc(badTok);
        
        Integer[] highlights = new Integer[]{ badTok.index, badTok.index + badTok.lexeme.length() };
            if (badTok.ttype == SOQLLexer.EOF) {
                if (badTok.penTok != null) {
                    highlights[0] = badTok.penTok.index;
                }
                highlights[1] = badTok.index;
            }
        if (addlHighlights != null) {
            for (SOQLLexer.Token tok : addlHighlights) {
                highlights.addAll(new Integer[]{ tok.index, tok.index + tok.lexeme.length() });
            }
        }
        err(badTok, new ParseException(msg), highlights);
        //err(loc, new ParseException(errMsg + '; got ' + loc.lexeme + loc(loc)));
    }
    
    static void refErr(SOQLLexer.Token loc, String msg) {
        err(loc, new ReferenceException(msg + loc(loc)));
    }
    
    static void typeErr(SOQLLexer.Token loc, String msg) {
        err(loc, new TypeException(msg + loc(loc)));
    }
    
    static void serErr(SOQLLexer.Token loc, String msg) {
        err(loc, new SerializerException(msg + loc(loc)));
    }
    
    public static void evalErr(SOQLLexer.Token loc, String msg) {
        err(loc, new EvaluationException(msg + loc(loc)));
    }
    
    static void err(SOQLLexer.Token loc, ErrorException err) {
        Integer[] highlights;
        if (loc != null) {
            highlights = new Integer[2];
            highlights[0] = loc.index;
            if (loc.ttype == SOQLLexer.EOF) {
                highlights[1] = loc.index;
            } else {
                highlights[1] = loc.lexeme != null ? loc.index + loc.lexeme.length() : loc.index;
            }
        }
        err(loc, err, highlights);
    }
    
    static void err(SOQLLexer.Token loc, ErrorException err, Integer[] highlights) {
        SOQLParser.error = err;
        SOQLParser.errorLoc = loc;
        SOQLParser.errorHighlights = highlights;
        throw err;
    }
    
    public static String loc(SOQLLexer.Token loc) {
        return (loc.injected ? ' - <Injected Code> at ' : ' - at ') + (loc.index == null ? '<Unknown Code Location>' : 'line: ' + (loc.line + 1) + ', col: ' + (loc.col + 1));
    }
    
    static void matchDateLiteral(SOQLLexer lex, ValueElmt valueElmt, SOQLLexer.Token yearTok, SOQLLexer.Token monthTok) {
        SOQLLexer.Token[] toks = lex.toks;
        Integer iYear = Integer.valueOf(yearTok.lexeme);
        Integer iMonth = Integer.valueOf(monthTok.lexeme);
        if (iMonth == 0 || iMonth > 12) {
            // parse error; invalid month
            mismatch(monthTok, 'Date expression\'s month component must be between 1 and 12');
        }
        Integer iDay;
        SOQLLexer.Token tok;
        
        // consume a '-' separator:
        if ((tok = toks[lex.next++]).ttype != SOQLLexer.MINUS) {
            // parse error; expected day component to date
            mismatch(tok, 'Date expression expected a day component');
        }
        // consume a day component:
        if ((tok = toks[lex.next++]).ttype != SOQLLexer.DECIMAL_NUMBER || tok.lexeme.contains('.')) {
            // parse error; day component of date must be integer not decimal
            mismatch(tok, 'Date expression\'s day component must be an integer');
        }
        try {
            iDay = Integer.valueOf(tok.lexeme);
        } catch (Exception e) {
            // parse error; day component of time is too big for Integer
            mismatch(tok, 'Date expression\'s day component is too big');
        }
        if (iDay == 0 || iDay > 31) {
            // parse error; invalid day component
            mismatch(tok, 'Date expression\'s day component must be between 1 and 31');
        }
        
        Date dateLit;
        try {
            dateLit = Date.newInstance(iYear, iMonth, iDay);
        } catch (Exception e) {
            // parse error; invalid date literal value (e.g. Feb. 30)
            parseErr(yearTok, 'Date expression specifies an impossible date: ' + iYear + '-' + iMonth + '-' + iDay);
        }
        SOQLLexer.Token peekTok = toks[lex.next];
        // determine whether we should parse a time by looking for 'T'; note that this will likely be smashed together with the following
        // 'hh' component as a NAME token, so we have logic to check for this and separate them out:
        if (peekTok.lexeme.startsWithIgnoreCase('T')) {
            String aHours;
            // if we got the 'T' token combined with the 'hh' component of time as a NAME token:
            if (peekTok.lexeme.length() > 1 ) {
                tok = toks[lex.next++];
                aHours = tok.lexeme.substring(1, tok.lexeme.length());
                if (!aHours.isNumeric()) {
                    parseErr(peekTok, 'DateTime expression\'s hours component is not a valid integer');
                }
            // else we received the 'T' NAME token separately from the 'hh' (presumed to be a DECIMAL_NUMBER) component of time:
            // TODO: this branch should not be reachable given the current lexer impl; we'll always get a combined NAME token...
            } else {
                // advance past the 'T'
                lex.next++;
                // consume the expected 'hh' token:
                tok = toks[lex.next++];
                aHours = tok.lexeme;
                if (tok.ttype != SOQLLexer.DECIMAL_NUMBER) {
                    // parse error; expected hours component of time
                    mismatch(tok, 'DateTime expression expected an hours component');
                } else if (tok.lexeme.contains('.')) {
                    // parse error; hours component of time is malformed
                    mismatch(tok, 'DateTime expression\'s hours component must be an integer');
                }
            }
            
            Integer iHours;
            try {
                iHours = Integer.valueOf(aHours);
            } catch (Exception e) {
                // parse error; hours component of time is too big for Integer
                mismatch(tok, 'DateTime expression\'s hours component is too big');
            }
            if (iHours > 23) {
                // parse error; hours component of time is invalid
                mismatch(tok, 'DateTime expression\'s hours component must be between 0 and 23');
            }
            
            // minutes:
            if (toks[lex.next++].ttype != SOQLLexer.COLON) {
                // parse error; expected :minutes component of time
                mismatch(toks[lex.next - 1], 'DateTime expression expected a minutes component');
            }
            tok = toks[lex.next++];
            if (tok.ttype != SOQLLexer.DECIMAL_NUMBER || tok.lexeme.contains('.')) {
                // parse error; expected an integer minutes component of time
                mismatch(tok, 'DateTime expression\'s minutes component must be an integer');
            }
            Integer iMinutes;
            try {
                iMinutes = Integer.valueOf(tok.lexeme);
            } catch (Exception e) {
                // parse error; minutes component of time is too big for Integer
                mismatch(tok, 'DateTime expression\'s minutes component is too big');
            }
            if (iMinutes > 59) {
                // parse error; minutes component of time is invalid
                mismatch(tok, 'DateTime expression\'s minutes component must be less than 60');
            }
            
            // seconds:
            if (toks[lex.next++].ttype != SOQLLexer.COLON) {
                // parse error; expected :seconds component of time
                mismatch(toks[lex.next - 1], 'DateTime expression expected a seconds component');
            }
            tok = toks[lex.next++];
            if (tok.ttype != SOQLLexer.DECIMAL_NUMBER) {
                // parse error; expected seconds component of time
                mismatch(tok, 'DateTime expression\'s seconds component must be a number');
            }
            Decimal dSeconds = Decimal.valueOf(tok.lexeme);
            if (dSeconds >= 60) {
                // parse error; seconds component of time is invalid
                mismatch(tok, 'DateTime expression\'s seconds component must be less than 60');
            }
            
            // offset:
            Integer offsetPolarity = -1;
            Integer offsetHours = 0;
            Integer offsetMinutes = 0;
            tok = toks[lex.next++];
            Boolean parseOffset = false;
            if (tok.ttype == SOQLLexer.MINUS || tok.ttype == SOQLLexer.PLUS) {
                parseOffset = true;
                if (tok.ttype == SOQLLexer.MINUS) {
                    offsetPolarity = 1;
                }
            } else if (tok.lexeme != 'Z') {
                // parse error; expected timezone offset component of time
                mismatch(tok, 'DateTime expression requires a timezone-offset (Z or +hh:mm or -hh:mm) to follow the time component');
            }
            
            if (parseOffset) {
                // offset hours:
                tok = toks[lex.next++];
                if (tok.ttype != SOQLLexer.DECIMAL_NUMBER || tok.lexeme.contains('.')) {
                    // parse error; expected offset hours component of time
                    mismatch(tok, 'DateTime expression expected an integer timezone-offset hours component');
                }
                try {
                    offsetHours = offsetPolarity * Integer.valueOf(tok.lexeme);
                } catch (Exception e) {
                    // parse error; offset hours is too big for Integer
                    mismatch(tok, 'DateTime expression\'s timezone-offset hours component is too big');
                }
                
                // optional offset minutes:
                peekTok = toks[lex.next];
                if (peekTok.ttype == SOQLLexer.COLON) {
                    lex.next++;
                    tok = toks[lex.next++];
                    if (tok.ttype != SOQLLexer.DECIMAL_NUMBER || tok.lexeme.contains('.')) {
                        // parse error; expected offset minutes component of time
                        mismatch(tok, 'DateTime expression expected an integer timezone-offset minutes component');
                    }
                    try {
                        offsetMinutes = offsetPolarity * Integer.valueOf(tok.lexeme);
                    } catch (Exception e) {
                        // parse error; offset minutes is too big for Integer
                        mismatch(tok, 'DateTime expression\'s timezone-offset minutes component is too big');
                    }
                }
            }
            
            // TODO: what if Math.floor(dSeconds) is bigger than MAX INT?
            Time timeLit = Time.newInstance(iHours, iMinutes, Math.floor(dSeconds).intValue(), ((dSeconds - Math.floor(dSeconds)) * 1000).intValue());
            valueElmt.dateTimeLit = DateTime.newInstanceGmt(dateLit, timeLit)
                .addHours(offsetHours)
                .addMinutes(offsetMinutes);
        } else {
            valueElmt.dateLit = dateLit;
        }
    }
    
    static void matchDateFormula(SOQLLexer lex, ValueElmt valueElmt, SOQLLexer.Token tok) {
        SOQLLexer.Token[] toks = lex.toks;
        valueElmt.dateFormula = tok;
        if (tok.ttype >= SOQLLexer.KW_DATE_FORMULA_N_KEYWORD_MINIMUM) {
            if (toks[lex.next++].ttype != SOQLLexer.COLON) {
                // parse error; this date formula requires an :intParam
                mismatch(tok, 'Date Formula ' + tok.lexeme.toUpperCase() + ' requires a subsequent colon and integer N value');
            }
            tok = toks[lex.next++];
            Integer nPolarity = 1;
            if (tok.ttype == SOQLLexer.MINUS) {
                nPolarity = -1;
                tok = toks[lex.next++];
            } else if (tok.ttype == SOQLLexer.PLUS) {
                tok = toks[lex.next++];
            }
            
            if (tok.ttype != SOQLLexer.DECIMAL_NUMBER || tok.lexeme.contains('.')) {
                // parse error; this date formula requires an intParam
                mismatch(tok, 'Date Formula ' + tok.lexeme.toUpperCase() + '\'s N value must be an integer');
            }
            try {
                valueElmt.dateFormula_N = nPolarity * Integer.valueOf(tok.lexeme);
            } catch (Exception e) {
                // parse error; intParam is too big for Integer
                mismatch(tok, 'Date Formula ' + tok.lexeme.toUpperCase() + '\'s N value is too big');
            }
        }
    }
    
    public static final OrExpr OrExprProto = new OrExpr();
    public static final AndExpr AndExprProto = new AndExpr();
    public static final NotExpr NotExprProto = new NotExpr();
    public static final SimpleExpr SimpleExprProto = new SimpleExpr();
    public static final RefExpr RefExprProto = new RefExpr();
    
    static {
        OrExprProto.lvl     = 0;
        AndExprProto.lvl    = 1;
        NotExprProto.lvl    = 2;
        SimpleExprProto.lvl = 3;
        RefExprProto.lvl    = 4;
    }
}