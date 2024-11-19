public with sharing class RKUtils {

    static final Schema.SObjectType PackageObject = Schema.Audio_System__c.SObjectType;
    //static final Schema.SObjectType PackageObject = Schema.Risks__c.SObjectType;
    static final Pattern SortDirPatt = Pattern.compile('(?i)(ASC|DESC)(\\s++NULLS\\s++(FIRST|LAST))?|NULLS\\s++(FIRST|LAST)');

    public static String sortDir(String sortDir) {
        if (sortDir == null) {
            return '';
        } else if (String.isBlank(sortDir) || SortDirPatt.matcher(sortDir.trim()).matches()) {
            return sortDir;
        } else {
            System.debug('Sort direction [' + sortDir + '] is invalid');
            System.assert(false, 'Query sort direction is invalid');
        }
        return null; // unreachable
    }

    public static Schema.SObjectType fromClause(String target) {    
        Schema.SObjectType targetType = resolveSObjectType(target);
        if (targetType == null) {
            System.debug('Object named [' + target + '] does not exist');
            System.assert(false, 'Query target Object does not exist on org');
        }
        return targetType;
    }

    public static Schema.SObjectType safeFromClause(String target) {    
        Schema.SObjectType targetType = fromClause(target);
        if (!targetType.getDescribe().isAccessible()) {
            System.debug('Object ' + targetType + ' is not Readable for User ' + UserInfo.getUserName());
            System.assert(false, 'Query target Object is not Readable');
        }
        return targetType;
    }
    
    public static String safeSelectPaths(String objectName, String safePaths) {
        return mixedSelectPaths(objectName, null, new String[]{ safePaths }, null);
    }

    public static String safeSelectPaths(String objectName, String[] safePaths) {
        return mixedSelectPaths(objectName, null, safePaths, null);
    }

    public static String selectPaths(String objectName, String systemPaths) {
        return mixedSelectPaths(objectName, new String[]{ systemPaths }, null, null);
    }

    public static String selectPaths(String objectName, String systemPaths, String bypassExplanation) {
        return mixedSelectPaths(objectName, new String[]{ systemPaths }, null, bypassExplanation);
    }

    public static String selectPaths(String objectName, String[] systemPaths) {
        return mixedSelectPaths(objectName, systemPaths, null, null);
    }

    public static String selectPaths(String objectName, String[] systemPaths, String bypassExplanation) {
        return mixedSelectPaths(objectName, systemPaths, null, bypassExplanation);
    }

    // Example:
    // String query = 
    //     'SELECT ' + RKUtils.mixedSelectPaths('Access_Log__c', 
    //         'Access_Type__c Field__c New_Value__c', 
    //         'CreatedBy__c.Name Object_Type__c Old_Value__c ParentId__c') + 
    //     ' FROM ' + RKUtils.safeFromClause('Access_Log__c'));
    public static String mixedSelectPaths(String objectName, String systemPaths, String safePaths) {
        return mixedSelectPaths(objectName, new String[]{ systemPaths }, new String[]{ safePaths }, null);
    }

    public static String mixedSelectPaths(String objectName, String systemPaths, String safePaths, String bypassExplanation) {
        return mixedSelectPaths(objectName, new String[]{ systemPaths }, new String[]{ safePaths }, bypassExplanation);
    }

    public static String mixedSelectPaths(String objectName, String[] systemPaths, String[] safePaths) {
        return mixedSelectPaths(objectName, systemPaths, safePaths, null);
    }

    public static String mixedSelectPaths(String objectName, String[] systemPaths, String[] safePaths, String bypassExplanation) {
        Schema.sObjectType sobjType = resolveSObjectType(objectName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + objectName + ']');
        }
        Boolean SecureAccessMode = false;
        Map<String, PathPart> selMap = systemPaths != null ? selectMapLogic(SecureAccessMode, false, sobjType, systemPaths, null) : new Map<String, PathPart>();
        if (safePaths != null) {
            SecureAccessMode = true;
            selMap.putAll(selectMapLogic(SecureAccessMode, false, sobjType, safePaths, null));
        }
        if (selMap.keySet().isEmpty()) {
            return 'Id'; //new Set<String>{ 'Id' };
        } else {
            return String.join(new List<String>(selMap.keySet()), ',');
        }    
    }

    public static String sortPath(String objectName, String fieldPath, String bypassExplanation) {
        return sortPath(false, objectName, fieldPath, bypassExplanation);
    }

    public static String safeSortPath(String objectName, String fieldPath) {
        return sortPath(true, objectName, fieldPath, null);
    }

    private static String sortPath(Boolean safeAccessMode, String objectName, String fieldPath, String bypassExplanation) {
        Schema.sObjectType sobjType = resolveSObjectType(objectName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + objectName + ']');
        }
        Map<String, PathPart> targetsMap = selectMapLogic(safeAccessMode, false, sobjType, new String[]{ fieldPath }, null);
        if (targetsMap.keySet().size() != 1) {
            System.debug('ORDER BY target [' + fieldPath + '] is invalid - ' + (targetsMap.keySet().isEmpty() ? 'no targets' : 'multiple targets'));
            System.assert(false, 'ORDER BY target is invalid');
        }
        String targetPath = new List<String>(targetsMap.keySet())[0];
        return targetPath;
    }

    private static Map<String, Schema.SObjectType> globalDescribe;
    private static Map<String, Schema.ChildRelationship> childRelationships = new Map<String, Schema.ChildRelationship>();

    public static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        return globalDescribe;
    }

    public static Schema.SObjectType getSObjectType(String sObjectName) {
        return getGlobalDescribe().get(sObjectName);
    }

    private static Boolean SystemModeOverride = false;

    public static final Integer BYPASS_FLS_CRUD           = -1;
    public static final Integer FILTER_FLS_CRUD           =  0;
    public static final Integer FILTER_FLS_THROW_CRUD     =  1;
    //public static final Integer ALL_OR_NONE_TRANSACTIONAL =  2;
    public static final Integer ALL_OR_NONE               =  2; //3;

    private static Integer SecurityMode = ALL_OR_NONE; //FILTER_FLS_THROW_CRUD;
    private static Boolean SecurityModeTransactional = false;

    private static Map<Schema.sObjectType, Integer> CRUDMissMap;
    private static Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>> FLSMissMap;
    
    private static String PackageNamespace;
    private static String OrgNamespace;
    private static Pattern ObjFieldPatt = Pattern.compile('(?i)^(?:([a-z][a-z0-9]*)__)?([a-z](?:[a-z0-9]|_(?!_))++(?:__c|__r|__latitude__s|__longitude__s))$');
    private static Pattern NamespaceQualifiedObjFieldPatt = Pattern.compile('(?i)^([a-z][a-z0-9]++)__([a-z](?:[a-z0-9]|_(?!_))++(?:__c|__r|__latitude__s|__longitude__s))$');
    private static Pattern NamespaceQualifiedFieldSetOrRecordTypePatt = Pattern.compile('(?i)^([a-z][a-z0-9]++)__([a-z](?:[a-z0-9]|_(?!_|$))++)$');
    // pattern for crudely macthing anything that "looks like" and API name path, including some invalid ones (e.g. valid: Foo__r.Bar__c; invalid: __Foo__c, 0Foo__c)
    public static Pattern CrudeIdentifyApiPathPatt = Pattern.compile('(?i)[a-z_0-9]++(?:\\.[a-z_0-9]++)*+');

    public static String getPackageNamespace() {
        if (PackageNamespace == null) {
            String qualifiedName = '' + PackageObject; // known argrc packaged Object
            Matcher m = NamespaceQualifiedObjFieldPatt.matcher(qualifiedName);
            if (m.matches()) {
                PackageNamespace = m.group(1);
                if (String.isBlank(PackageNamespace)) {
                    PackageNamespace = 'c';
                }
            } else {
                PackageNamespace = 'c';
            }
        }
        return PackageNamespace == 'c' ? null : PackageNamespace;
    }

    public static String getOrgNamespace() {
        if (OrgNamespace == null) {
            OrgNamespace = [ SELECT NamespacePrefix FROM Organization LIMIT 1].NamespacePrefix;
            if (String.isBlank(OrgNamespace)) {
                OrgNamespace = 'c';
            }
        }
        return OrgNamespace == 'c' ? null : OrgNamespace;
    }

    // primitive bind types:
    public static final Integer BIND_DYNAMIC = 0;
    public static final Integer BIND_PKG_STATIC = 1;
    public static final Integer BIND_ORG_STATIC = 2;
    // compound bind types below here:
    public static final Integer BIND_PGK_STATIC_THEN_DYNAMIC = 3;
    public static final Integer BIND_ORG_STATIC_THEN_DYNAMIC = 4;
    public static final Integer BIND_DYNAMIC_THEN_PKG_STATIC = 5;
    public static final Integer BIND_DYNAMIC_THEN_ORG_STATIC = 6;

    private static final List<Integer[]> BindStrategyStack = new List<Integer[]>{ new Integer[]{ BIND_PKG_STATIC, BIND_DYNAMIC } };

    private static Integer[] resolvePrimitiveBindTypes(Integer bindType) {
        if (bindType == BIND_PGK_STATIC_THEN_DYNAMIC) {
            return new Integer[]{ BIND_PKG_STATIC, BIND_DYNAMIC };
        } else if (bindType == BIND_ORG_STATIC_THEN_DYNAMIC) {
            return new Integer[]{ BIND_ORG_STATIC, BIND_DYNAMIC };
        } else if (bindType == BIND_DYNAMIC_THEN_PKG_STATIC) {
            return new Integer[]{ BIND_DYNAMIC, BIND_PKG_STATIC };
        } else if (bindType == BIND_DYNAMIC_THEN_ORG_STATIC) {
            return new Integer[]{ BIND_DYNAMIC, BIND_ORG_STATIC };
        } else if (bindType != null && bindType >= 0 && bindType <= 2) {
            return new Integer[]{ bindType };
        } else {
            bindTypeInvalidErr(bindType);
            return null; // unreachable
        }
    }
    @TestVisible
    static void bindTypeInvalidErr(Integer badBindType) {
        throw new AuraHandledException('Binding type ' + badBindType + ' is invalid');
    }

    public static void startBinding(Integer bindingType) {
        BindStrategyStack.add(resolvePrimitiveBindTypes(bindingType));
    }

    public static void revertBinding() {
        if (BindStrategyStack.size() > 1) {
            BindStrategyStack.remove(BindStrategyStack.size() - 1);
        }
    }

    public static void revertToDefaultBinding() {
        while (BindStrategyStack.size() > 1) {
            BindStrategyStack.remove(1);
        }
    }

    public static Schema.sObjectType resolveSObjectType(String typeName) {
        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.sObjectType resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedFieldSetOrRecordTypePatt.matcher(typeName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches()) {
                    resolved = getGlobalDescribe().get(typeName);
                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    //resolved = fsMap.get((ns != null ? ns + '__' : '') + fieldSetName);
                    resolved = getGlobalDescribe().get((ns != null ? ns + '__' : '') + typeName);
                }
            } else { // BIND_DYNAMIC
                resolved = getGlobalDescribe().get(typeName);
            }
        } while (resolved == null && bindStrat.size() > 0);

        return resolved;
    }

    public static String joinSelect(String selsLeft, String selsRight) {
        selsLeft = selsLeft != null ? selsLeft.replaceAll('\\s++', '').replaceAll('^[,]++|[,]++$', '') : null;
        selsRight = selsRight != null ? selsRight.replaceAll('\\s++', '').replaceAll('^[,]++|[,]++$', '') : null;
        if (String.isNotBlank(selsLeft) && String.isNotBLank(selsRight)) {
            return selsLeft + ',' + selsRight;
        } else if (String.isNotBlank(selsLeft)) {
            return selsLeft;
        } else if (String.isNotBlank(selsRight)) {
            return selsRight;
        } else {
            return 'Id';
        }
    }

    // For the safeSelect calls below, a "selectElement" can be any of the following:
    //   * A Field API name e.g. 'My_Field__c'
    //   * A field path e.g. 'Parent_Lookup__r.My_Other_Field__c'
    //   * A FieldSet name e.g. 'My_Field_Set'
    //   * A delimited list of any of the above - any combination of spaces, commas, colons, semicolons etc can be used as delimiters 
    //     e.g. 'My_Field__c, Parent_Lookup__r.My_Other_Field__c, My_Field_Set'
    // 
    // All safeSelect methods return a comma-delimited list of field names that can be used as the target of a SOQL SELECT clause; FieldSets will be 
    // automatically expanded. Field-Level Security and CRUD permissions will be enforced for the context user (TODO: soon); fields for which the 
    // user is lacking visibility will simply be stripped from the result string.
    //
    // Example usage:
    // Database.query('SELECT ' + RKSecurity.safeSelect(Schema.My_Table__c.sObjectType, 'My_Field__c, Parent_Lookup__r.My_Other_Field__c, My_Field_Set') + ' FROM My_Table__c'); 

    public static String systemSelect(String sobjTypeName, String selectElement) {
        return systemSelect(sobjTypeName, new List<String>{ selectElement }, null);
    }

    public static String systemSelect(String sobjTypeName, String selectElement, Integer oneTimeBindingStratregy) {
        return systemSelect(sobjTypeName, new List<String>{ selectElement }, oneTimeBindingStratregy);
    }

    public static String systemSelect(String sobjTypeName, List<String> selectElements) {
        return systemSelect(sobjTypeName, selectElements, null);
    }

    public static String systemSelect(String sobjTypeName, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String systemSelect(Schema.sObjectType sobjType, String selectElement) {
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, new List<String>{ selectElement }, null);
    }

    public static String systemSelect(Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        final Boolean SecureAccessMode = false;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }
    
    public static String safeSelect(String sobjTypeName, String selectElement) {
        return safeSelect(sobjTypeName, new List<String>{ selectElement }, null);
    }

    public static String safeSelect(String sobjTypeName, String selectElement, Integer oneTimeBindingStratregy) {
        return safeSelect(sobjTypeName, new List<String>{ selectElement }, oneTimeBindingStratregy);
    }

    public static String safeSelect(String sobjTypeName, List<String> selectElements) {
        return safeSelect(sobjTypeName, selectElements, null);
    }

    public static String safeSelect(String sobjTypeName, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Schema.sObjectType sobjType = resolveSObjectType(sobjTypeName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + sobjTypeName + ']');
        }
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String safeSelect(Schema.sObjectType sobjType, String selectElement) {
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, new List<String>{ selectElement }, null);
    }

    public static String safeSelect(Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        final Boolean SecureAccessMode = true;
        return selectLogic(SecureAccessMode, sobjType, selectElements, oneTimeBindingStratregy);
    }

    public static String selectLogic(Boolean isSafeMode, Schema.sObjectType sobjType, List<String> selectElements, Integer oneTimeBindingStratregy) {
        Set<String> sels = selectSetLogic(isSafeMode, true, sobjType, selectElements, oneTimeBindingStratregy);
        return String.join(new List<String>(sels), ',');
    }

    public static Set<String> selectSetLogic(Boolean isSafeMode, Boolean crudCheck, Schema.sObjectType sobjType, 
            List<String> selectElements, Integer oneTimeBindingStratregy) {

        Map<String, PathPart> selMap = selectMapLogic(isSafeMode, crudCheck, sobjType, selectElements, oneTimeBindingStratregy);
        if (selMap.keySet().isEmpty()) {
            return new Set<String>{ 'Id' };
        } else {
            return selMap.keySet();
        }
    }

    static final Pattern OrderByElementPatt = Pattern.compile('(?i)([a-z_0-9]++(?:\\.[a-z_0-9]++)*+)(\\s++(?:ASC|DESC)(\\s++NULLS\\s++(?:FIRST|LAST))?|\\s++NULLS\\s++(?:FIRST|LAST))?');

    public static String safeOrderByClause(String objectName, String orderBy) {
        return orderByClause(true, objectName, orderBy, null);
    }

    public static String orderByClause(String objectName, String orderBy) {
        return orderByClause(false, objectName, orderBy, null);
    }

    public static String orderByClause(String objectName, String orderBy, String bypassExplanation) {
        return orderByClause(false, objectName, orderBy, bypassExplanation);
    }

    public static String orderByClause(Boolean safeAccessMode, String objectName, String orderBy, String bypassExplanation) {
        Schema.sObjectType sobjType = resolveSObjectType(objectName);
        if (sobjType == null) {
            throw new ReferenceException('Invalid sObjectType [' + objectName + ']');
        }
        if (String.isBlank(orderBy)) {
            return null;
        }
        String[] serParts = new String[]{};
        for (String elmt : orderBy.split(',')) {
            if (String.isNotBlank(elmt)) {
                Matcher m = OrderByElementPatt.matcher(elmt.trim());
                if (m.matches()) {
                    Map<String, PathPart> selMap = selectMapLogic(safeAccessMode, false, sobjType, new String[]{ m.group(1) }, null);
                    if (selMap.keySet().isEmpty()) {
                        continue;
                    }
                    serParts.add(new List<String>(selMap.keySet())[0] + (String.isNotBlank(m.group(2)) ? ' ' + m.group(2).trim().toUpperCase() : ''));
                } else {
                    System.debug('ORDER BY target [' + elmt + '] is invalid');
                    System.assert(false, 'ORDER BY target is invalid');
                }
            }
        }
        
        return serParts.isEmpty() ? '' : ' ORDER BY ' + String.join(serParts, ', ');
    }

    // Note that the PathParts returned will be the leaves, i.e. terminating fields:
    public static Map<String, PathPart> selectMapLogic(Boolean isSafeMode, Boolean crudCheck, Schema.sObjectType sobjType, 
            List<String> selectElements, Integer oneTimeBindingStratregy) {

        resetSecurityLog(true);
        if (oneTimeBindingStratregy != null) {
            startBinding(oneTimeBindingStratregy);
        }
        try {
            // Skipping CRUD Read checks for now 
            //if (isSafeMode == true && crudCheck == true && !ReadChecker.checkCRUD(sobjType)) {
            //    // TODO: fix this
            //    return new Map<String, PathPart>{ 'NO_CRUD_READ_ACCESS_' + sobjType => null };
            //}
            Map<String, PathPart> resolvedFields = new Map<String, PathPart>(); // new Set<String>{ 'Id' };
            // parse out anything that looks like a valid SFDC api name:
            String elmtCat = String.join(selectElements, ','); //+ ',' + String.join(openSelElmts, ',');
            Matcher m = CrudeIdentifyApiPathPatt.matcher(elmtCat);
            PathPart[] headParts = new PathPart[]{};
            while (m.find()) {
                String elmt = m.group(0);
                // compound field paths will have their path parts delimited by the dot-operator:
                String[] rawPathParts = elmt.split('\\.');
                PathPart headPart = new PathPart(sobjType);
                try {
                    resolvePathBranch(headPart, rawPathParts, 0);
                } catch (Exception e) {
                    outErr(e);
                }
                headParts.add(headPart);
            }
            if (headParts.size() > 0) {
                Map<String, PathPart> resolvedPaths;
                if (isSafeMode == true) {
                    resolvedPaths = getSafeAccessPathsMap(headParts);
                } else {
                    resolvedPaths = getSystemAccessPathsMap(headParts);
                }
                resolvedFields.putAll(resolvedPaths);
            }
            return resolvedFields;
        } finally {
            if (oneTimeBindingStratregy != null) {
                revertBinding();
            }
            throwSecurityViolations(true);
        }
    }

    public static String getSafePath(Schema.sObjectType sobjType, String rawPath) {
        // Skipping CRUD Read checks for now 
        //if (String.isNotBlank(rawPath) && ReadChecker.checkCRUD(sobjType)) {
            String[] rawPathParts = rawPath.split('\\.');
            PathPart headPart = new PathPart(sobjType);
            resolvePathBranch(headPart, rawPathParts, 0);
            Set<String> resolvedPaths = getSafeAccessPaths(new PathPart[]{ headPart });
            if (resolvedPaths != null && resolvedPaths.size() > 0) {
                return new List<String>(resolvedPaths)[0];
            }
        //}
        return null;
    }

    public static PathPart getPathMeta(String rawPath, String sobjectName) {  //RKDEV-34816
        String[] rawPathParts = rawPath.split('\\.');
        Schema.SObjectType sObjectType = String.isBlank(sobjectName) ? PackageObject : getSObjectType(sObjectName);
        PathPart headPart = new PathPart(sObjectType);
        resolvePathBranch(headPart, rawPathParts, 0);
        return headPart;
    }
    
    public static PathPart getPathMeta(String rawPath) {
        String[] rawPathParts = rawPath.split('\\.');
        PathPart headPart = new PathPart(PackageObject);
        resolvePathBranch(headPart, rawPathParts, 0);
        return headPart;
    }

    public class PathPart {
        public PathPart head {get; private set;}
        public PathPart parent {get; private set;}
        public sObjectType holder {get; private set;}
        // next.size() is greater than 1 in the case of a fieldSet OR a field that is a polymorphic lookup:
        public PathPart[] next {get; private set;}
        public Schema.FieldSet fieldSet {get; private set;}
        public Schema.DescribeFieldResult fieldDesc {get; private set;}
        public String lex {get; private set;} // field or field set, with letter casing and suffix directly as pulled from the path string

        public Boolean isCompound {get{
            return this.next != null;
        }}

        public PathPart terminatingPart {get{
            if (terminatingPart == null) {
                PathPart term = this;
                while (term.next != null) {
                    term = term.next[0];
                }
                this.terminatingPart = term;
            }
            return terminatingPart;
        } private set; }

        public Boolean isTerminatingPart {get{
            return this === this.terminatingPart;
        }}

        private Boolean notSafeAccessible = false;

        public String safeAccessPath {get{
            if (safeAccessPath == null && !notSafeAccessible) {
                Set<String> safePaths = getSafeAccessPaths(new PathPart[]{ this });
                if (safePaths != null && safePaths.size() > 0) {
                    this.safeAccessPath = new List<String>(safePaths)[0];
                }
                this.notSafeAccessible = true;
            }
            return safeAccessPath;
        } private set; }

        // local accessibility flag, updated via the AccessibilityCompiler and AccessibilityCompilerPass2:
        Boolean accessible = false;

        PathPart(sObjectType holder) {
            this.head = this;
            this.holder = holder;
        }

        PathPart(PathPart parent, sObjectType holder) {
            this.head = parent.head;
            this.parent = parent;
            this.holder = holder;
        }

        void traverse(PathVisitor visitor) {
            if (visitor.visit(this) != false) {
                if (next != null) {
                    for (PathPart n : next) {
                        n.traverse(visitor);
                    }
                }
                if (visitor.doAfterVisit == true) {
                    visitor.afterVisit(this);
                }
            }
        }

        // Serializes the path from root to this specific node (not necessarily a leaf node):
        public String toNormalizedPath() {
            String[] revParts = new String[]{};
            PathPart part = this;
            // the node that this method is called on is the acting/effective tail part:
            Boolean onEffectiveTailPart = true;
            do {
                if (part.fieldDesc != null) {
                    String normName = part.fieldDesc.getName();
                    // even if this is a parent-ref __r part in the full path, if this the the acting tail part from being the initial method caller,
                    // it should serialize as a __c:
                    Boolean isRef = !onEffectiveTailPart && part.next != null;
                    if (isRef) {
                        if (normName.endsWith('Id') && normName != 'Id') {
                            revParts.add(normName.substring(0, normName.length() - 2));
                        } else if (normName.endsWithIgnoreCase('__c')) {
                            revParts.add(normName.substring(0, normName.length() - 3) + '__r');
                        } else {
                            revParts.add(normName);
                        }
                    } else {
                        revParts.add(normName);
                    }
                    onEffectiveTailPart = false;
                }
                part = part.parent;
            } while (part != null);
            // reverse the reverse-ordered parts before serialization:
            Integer len = revParts.size();
            for (Integer i=0; i < len / 2; i++) {
                String tmp = revParts[i];
                Integer counterpart = len - 1 - i;
                revParts[i] = revParts[counterpart];
                revParts[counterpart] = tmp;
            }
            return String.join(revParts, '.');
        }

        /*
        // JLB - Behaves pretty much the same as toNormalizedPath, but it additionally resolves any field names
        // with mock entries to their mock name. Useful for passing configurable field names to the client side
        // to allow dynamic field access
        public String toMockPath() {
            String[] revParts = new String[]{};
            PathPart part = this;
            // the node that this method is called on is the acting/effective tail part:
            Boolean onEffectiveTailPart = true;
            do {
                if (part.fieldDesc != null) {
                    String normName = part.fieldDesc.getName();
                    // even if this is a parent-ref __r part in the full path, if this the the acting tail part from being the initial method caller,
                    // it should serialize as a __c:
                    Boolean isRef = !onEffectiveTailPart && part.next != null;
                    if (isRef) {
                        if (normName.endsWith('Id') && normName != 'Id') {
                            normName = normName.substring(0, normName.length() - 2);
                        } else if (normName.endsWithIgnoreCase('__c')) {
                            normName = normName.substring(0, normName.length() - 3) + '__r';
                        }
                    }

                    // Resolve mock field name (will return originally passed value is no match found)
                    normName = RKMock.resolveToMockKey(part.holder, normName);
                    revParts.add(normName);

                    onEffectiveTailPart = false;
                }
                part = part.parent;
            } while (part != null);
            // reverse the reverse-ordered parts before serialization:
            Integer len = revParts.size();
            for (Integer i=0; i < len / 2; i++) {
                String tmp = revParts[i];
                Integer counterpart = len - 1 - i;
                revParts[i] = revParts[counterpart];
                revParts[counterpart] = tmp;
            }
            return String.join(revParts, '.');
        }
        */

        public Object getValue(sObject sobj, Boolean safeAccessFlag) {
            ValueGetter getter = new ValueGetter(sobj).safeAccess(safeAccessFlag);
            getter.exec(new PathPart[]{ this });
            return getter.leafValue;
        }
    }

    abstract class PathVisitor {
        Boolean doAfterVisit;

        PathVisitor(Boolean doAfterVisit) {
            this.doAfterVisit = doAfterVisit == true;
        }

        virtual void exec(PathPart[] headParts) {
            for (PathPart headPart : headParts) {
                System.assert(headPart.head === headPart, 'Visitor exec can only be called on head parts');
                headPart.traverse(this);
            }
        }
        
        virtual Boolean visit(PathPart part) { return true; } // no-op by default

        virtual void afterVisit(PathPart part) {} // no-op by default
    }

    // TODO: this seems redundant to getSystemAccessPaths()...
    static Set<String> getAllPaths(PathPart[] headParts) {
        SystemAccessCompiler compiler = new SystemAccessCompiler();
        compiler.exec(headParts);
        return compiler.fullPathsMap.keySet();
    }

    public static String getSystemAccessPath(PathPart headPart) {
        Set<String> path = getSystemAccessPaths(new PathPart[]{ headPart });
        return path != null && !path.isEmpty() ? new List<String>(path)[0] : null; 
    }

    public static Set<String> getSystemAccessPaths(PathPart[] headParts) {
        return getSystemAccessPathsMap(headParts).keySet();
    }

    public static Map<String, PathPart> getSystemAccessPathsMap(PathPart[] headParts) {
        SystemAccessCompiler compiler = new SystemAccessCompiler();
        compiler.exec(headParts);
        return compiler.fullPathsMap;
    }

    public static Map<String, PathPart> getSafeAccessPathsMap(PathPart[] headParts) {
        resetSecurityLog(true);
        new SafeAccessCompiler().exec(headParts);
        SafeAccessPass2 pass2 = new SafeAccessPass2();
        pass2.exec(headParts);
        throwSecurityViolations(true);
        return pass2.safePathsMap;
    }

    public static Set<String> getSafeAccessPaths(PathPart[] headParts) {
        return getSafeAccessPathsMap(headParts).keySet();
    }

    class SystemAccessCompiler extends PathVisitor {
        //Set<String> fullPaths = new Set<String>();
        Map<String, PathPart> fullPathsMap = new Map<String, PathPart>();

        SystemAccessCompiler() {
            super(false);
        }

        override Boolean visit(PathPart part) {
            if (part.fieldDesc != null && part.next == null) {
                //fullPaths.add(part.toNormalizedPath());
                // !! Note that we return the leaf (i.e. terminating) part of the path, useful for field describe metadata:
                fullPathsMap.put(part.toNormalizedPath(), part);
            }
            return true;
        }
    }

    class SafeAccessCompiler extends PathVisitor {
        SafeAccessCompiler() {
            super(true);
        }

        override Boolean visit(PathPart part) {
            // We only verify FLS Read security on the terminating part (i.e. the final target field of a path):
            if (part.isTerminatingPart) {
                // note that FieldSets get a pass-through because they don't have their own security 
                if (part.fieldDesc != null) {
                    // TODO: check CRUD "R" access on the part's holder object type...
                    part.accessible = part.fieldDesc.isAccessible();
                    if (!part.accessible) {
                        logSecurityMiss(part.holder, part.fieldDesc.getSObjectField(), ACCESS_READ);
                    }
                // field sets are always pass-through accessiblity becasue they do not have their own security:
                } else if (part.fieldSet != null) {
                    part.accessible = true;
                }
            } else {
                part.accessible = true;
            }
            return part.accessible;

            /*
            Boolean parentAccessible = part.parent != null ? part.parent.accessible : true;
            // a child cannot be accessed if any of the parent lookup relationships in its field path are not accessible:
            if (!parentAccessible) {
                part.accessible = false;
            } else {
                // note that FieldSets get a pass-through because they don't have their own security 
                if (part.fieldDesc != null) {
                    // TODO: check CRUD "R" access on the part's holder object type...
                    part.accessible = part.fieldDesc.isAccessible();
                    if (!part.accessible) {
                        logSecurityMiss(part.holder, part.fieldDesc.getSObjectField(), ACCESS_READ);
                    }
                // field sets are always pass-through accessiblity becasue they do not have their own security:
                } else if (part.fieldSet != null) {
                    part.accessible = true;
                }
            }
            // short-circuit further traversal if this path node has been deemed non-accessible:
            return part.accessible;
            */
        }

        override void afterVisit(PathPart part) {
            // polymorphic lookups require ALL of their 'next' fields be accessible; if they are not, then we correct its accessibility to false in this phase:
            if (part.accessible && part.fieldDesc != null && part.next != null && part.next.size() > 1) {
                for (PathPart next : part.next) {
                    if (!next.accessible) {                        
                        part.accessible = false;
                        break;
                    }
                }
            }
        }
    }

    class SafeAccessPass2 extends PathVisitor {
        //Set<String> safePaths = new Set<String>();
        Map<String, PathPart> safePathsMap = new Map<String, PathPart>();

        SafeAccessPass2() {
            super(false);
        }

        override Boolean visit(PathPart part) {
            Boolean parentAccessible = part.parent != null ? part.parent.accessible : true;
            // inaccessible parents re-cascade their inaaccessibility down towards their leaf descendants - note that this re-cascade in pass 2 is only necessary 
            // becasue of polymorphic lookups:
            if (!parentAccessible) {
                part.accessible = false;
            }
            // if this is a leaf node, and it's flagged as accessible at this point, then its full path has been determined to be accessible and we can add it to
            // the final result set:
            if (part.accessible && part.next == null) {
                //safePaths.add(part.toNormalizedPath());
                // !! Note that we return the leaf (i.e. terminating) part of the path, useful for field describe metadata:
                safePathsMap.put(part.toNormalizedPath(), part);
            }
            // again, short circuit traversal when we determine a path node to be inaccessible:
            return part.accessible;
        }
    }

    class ValueGetter extends PathVisitor {
        Boolean safeAccess = true;
        Object leafValue;
        sObject leafHolder;
        sObject[] holderStack = new sObject[]{};

        ValueGetter(sObject headHolder) {
            super(true);
            this.holderStack = new sObject[]{ headHolder };
        }

        ValueGetter safeAccess(Boolean safeAccess) {
            this.safeAccess = safeAccess == true;
            return this;
        }

        override Boolean visit(PathPart part) {
            if (part.fieldDesc != null) {
                if (safeAccess && !part.fieldDesc.isAccessible()) {
                    logSecurityMiss(part.holder, part.fieldDesc.getSObjectField(), ACCESS_READ);
                    return false;
                }
                Integer top = holderStack.size() - 1;
                sObject holder = holderStack[top];
                if (part.next == null) { // if leaf field
                    this.leafValue = holder != null ? holder.get(part.fieldDesc.getName()) : null;
                    this.leafHolder = holder;
                } else {
                    String relName = part.fieldDesc.getName().replaceFirst('(?i)Id$', '').replaceFirst('(?i)__c$', '__r');
                    holderStack.add(holder != null ? holder.getSObject(relName) : null);
                }
            }
            return true;
        }

        override void afterVisit(PathPart part) {
            if (part.fieldDesc != null) {
                if (part.next != null) { // if not leaf field
                    holderStack.remove(holderStack.size() - 1);
                }
            }
        }
    }

    // throws FieldPathException
    static void resolvePathBranch(PathPart currentPart, String[] rawParts, Integer rawIndex) { //, Map<String, Schema.sObjectType> polyLkpHints) {
        final Integer rawLen = rawParts.size();
        do {
            // MDU: Updated to automatically resolve aliases on fields and parent relationships, for use by the enhanced SOQLParser:
            String lexRaw = currentPart.lex = rawParts[rawIndex];
            // No alias mappings (mock keys) for now:
            //String lexMapped = RKMock.resolveMockKey(currentPart.holder, lexRaw);
            //String lex = lexMapped != null ? lexMapped : lexRaw;
            String lex = lexRaw;
            Boolean isRef = rawIndex < rawLen - 1;
            // if this lex token is not he the terminating token of the path, then it must be a parent reference:
            if (isRef) {
                String lkp;
                if (lex.endsWithIgnoreCase('__r')) {
                    lkp = lex.replaceFirst('(?i)__r$', '__c');
                } else if (!lex.endsWithIgnoreCase('Id') && !lex.endsWithIgnoreCase('__c')) {
                    lkp = lex + 'Id';
                } else {
                    lkp = lex;
                }
                Schema.sObjectField lkpField = resolveField(currentPart.holder, lkp);
                if (lkpField == null) {
                    throw new FieldPathException(
                        'Reference ' + (rawIndex > 0 ? '{' + currentPart.holder + '}.' : '') + lexRaw + (rawIndex > 0 ? ', in path "' + 
                            String.join(rawParts, '.') + '",' : '') + ' does not match a parent relationship');
                }
                currentPart.fieldDesc = lkpField.getDescribe();
                if (currentPart.fieldDesc.getType() != Schema.DisplayType.REFERENCE) {
                    throw new FieldPathException(
                        'Reference ' + (rawIndex > 0 ? '{' + currentPart.holder + '}.' : '') + lexRaw + (rawIndex > 0 ? ', in path "' + 
                        String.join(rawParts, '.') + '",' : '') + ' was expected to match a parent relationship; got ' + 
                        currentPart.fieldDesc.getType().name().toLowerCase() + ' field');
                }
                Schema.sObjectType[] refTos = currentPart.fieldDesc.getReferenceTo();
                // polymorphic lookup; we have to resort to recursion to resolve every possible parent object type:
                if (refTos.size() > 1) {
                    currentPart.next = new PathPart[]{};
                    for (Schema.sObjectType refTo : refTos) {
                        PathPart altPart = new PathPart(currentPart, refTo);
                        currentPart.next.add(altPart);
                        resolvePathBranch(altPart, rawParts, rawIndex + 1);
                    }
                    // the recursion will complete resolving the paths for all alternative parent types, so when we reach here we're done with 
                    // this loop:
                    break;
                // else, single-parent type lookup; we can setup next iteration and stay in this loops without recursing:
                } else {
                    rawIndex ++;
                    PathPart nextPart = new PathPart(currentPart, refTos[0]);
                    currentPart.next = new PathPart[]{ nextPart };
                    currentPart = nextPart;
                    continue;
                }
                // unreachable...
            // else lex is the terminating token of this path (though it could still be a FieldSet!):
            } else {
                Schema.sObjectField field = resolveField(currentPart.holder, lex);
                if (field == null) {
                    if (rawIndex > 0) {
                        throw new FieldPathException(
                            'Terminating identifier ' + lexRaw + ' for path "' + String.join(rawParts, '.') + 
                                '" does not match a Field on Object type ' + currentPart.holder);
                    } else {
                        throw new FieldPathException(
                            'Identifier ' + lexRaw + ' does not match a Field on Object type ' + currentPart.holder);
                    }
                    /*
                    Schema.FieldSet fieldSet = resolveFieldSet(currentPart.holder, lex);
                    if (fieldSet == null) {
                        if (rawIndex > 0) {
                            throw new FieldPathException(
                                'Terminating identifier ' + lexRaw + ' for path "' + String.join(rawParts, '.') + 
                                    '" does not match an existing Field or FieldSet on Object type ' + currentPart.holder);
                        } else {
                            throw new FieldPathException(
                                'Identifier ' + lexRaw + ' does not match an existing Field or FieldSet on Object type ' + currentPart.holder);
                        }
                    }
                    currentPart.fieldSet = fieldSet;
                    currentPart.next = new PathPart[]{}; //new PathPart(currentPart.head, currenPart.holder);
                    for (Schema.FieldSetMember mem : fieldSet.getFields()) {
                        PathPart recursePart = new PathPart(currentPart, currentPart.holder);
                        currentPart.next.add(recursePart);
                        String[] recurseRawParts = rawParts.clone();
                        recurseRawParts.addAll(mem.getFieldPath().split('\\.'));
                        resolvePathBranch(recursePart, recurseRawParts, rawIndex + 1);
                    }
                    // the recursion will complete resolving the paths for all alternative parent types, so when we reach here we're done with 
                    // this loop:
                    break;
                    */
                } else {
                    currentPart.fieldDesc = field.getDescribe();
                    break;
                }
                // unreachable...
            }
            // unreachable...
        } while (true);
    }

    public static Schema.sObjectField resolveField(Schema.sObjectType sobjType, String fieldName) {
        Map<String, Schema.sObjectField> fMapLC = FieldCacheLC.get(sobjType);
        if (fMapLC == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            FieldSetCacheLC.put(sobjType, normalizeFieldSetMapLC(sDesc));
            FieldCacheLC.put(sobjType, fMapLC = normalizeFieldMapLC(sDesc));
        }

        Integer[] bindStrat = BindStrategyStack[BindStrategyStack.size() - 1].clone();
        Schema.sObjectField resolved;
        do {
            Integer bindPrim = bindStrat.remove(0);
            /*
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedObjFieldPatt.matcher(fieldName);
                // if the requested fieldName already includes an explicit namespace qualification, then there's nothing more we can do other than to resolve 
                // it as-is:
                if (m.matches() && String.isNotBlank(m.group(1))) {
                    resolved = fMap.get(fieldName);

                // BIND_STATIC will automatically prepend this package namespace if (and only if) the requested fieldName does not already include a namespace
                // qualification. Note that "package namespace" refers to the namespace of the org where this code field resides (RK Questionnaire Framework),
                // which will differ from the namespace of any install/client target org that invokes this code: 
                } else {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    resolved = fMap.get((ns != null ? ns + '__' : '') + fieldName);
                }
            } else { // BIND_DYNAMIC
                resolved = fMap.get(fieldName);
            }
            */

            String mapKeyName = fieldName;
            if (bindPrim == BIND_PKG_STATIC || bindPrim == BIND_ORG_STATIC) {
                Matcher m = NamespaceQualifiedObjFieldPatt.matcher(fieldName);
                if (!m.matches() || String.isBlank(m.group(1))) {
                    String ns = bindPrim == BIND_PKG_STATIC ? getPackageNamespace() : getOrgNamespace();
                    mapKeyName = (ns != null ? ns + '__' : '') + fieldName;
                }
            }
            // MDU - 12/12/2018:
            // Added logic to detect a bogus field map key; it has been discovered that some local-only fields on package objects (e.g. 
            // Hierarchy__c on rkqf__Template_Question__c) will be dual-keyed, in the DescribeSObjectResult.fields.getMap() result, under 
            // the package namespace'd key (e.g. 'rkqf__Hierarchy__c'), even when no such package field counterpart exists. By stringifying 
            // the sObjectField token returned from the fields map (the stringified feld path is always correct), we can determine if this 
            // key value is really legit:
            //resolved = fMap.get(mapKeyName);
            resolved = fMapLC.get(mapKeyName != null ? mapKeyName.toLowerCase() : null);
            if (resolved != null && '' + resolved != mapKeyName) {
                resolved = null;
            }
        } while (resolved == null && bindStrat.size() > 0);

        if (resolved != null && !stripNamespace(fieldName).equals(stripNamespace('' + resolved))) {
            System.debug('IMPROPER CASE: ' + fieldName + ' => ' + resolved);
        }

        return resolved;
    }

    private static String stripNamespace(String field) {
        if (field == null) {
            return null;
        }
        Matcher m = NamespaceQualifiedObjFieldPatt.matcher(field);
        if (m.matches()) {
            return m.group(2);
        }
        return field;
    }

    private static Map<Schema.sObjectType, Map<String, Schema.RecordTypeInfo>> RecordTypeCache = new Map<Schema.sObjectType, Map<String, Schema.RecordTypeInfo>>();
    private static Map<Schema.sObjectType, Map<String, Schema.FieldSet>> FieldSetCacheLC = new Map<Schema.sObjectType, Map<String, Schema.FieldSet>>();
    private static Map<Schema.sObjectType, Map<String, Schema.sObjectField>> FieldCacheLC = new Map<Schema.sObjectType, Map<String, Schema.sObjectField>>();

    static Map<String, Schema.SObjectField> normalizeFieldMapLC(Schema.DescribeSObjectResult oDesc) {
        Map<String, Schema.sObjectField> fMapLC = new Map<String, Schema.SObjectField>();
        Map<String, Schema.sObjectField> fMap = oDesc.fields.getMap();
        if (fMap != null) {
            for (String f : fMap.keySet()) {
                fMapLC.put(f.toLowerCase(), fMap.get(f));
            }
        }
        return fMapLC;
    }

    static Map<String, Schema.FieldSet> normalizeFieldSetMapLC(Schema.DescribeSObjectResult oDesc) {
        Map<String, Schema.FieldSet> fsMapLC = new Map<String, FieldSet>();
        Map<String, Schema.FieldSet> fsMap = oDesc.fieldSets.getMap();
        if (fsMap != null) {
            for (String fs : fsMap.keySet()) {
                fsMapLC.put(fs.toLowerCase(), fsMap.get(fs));
            }
        }
        return fsMapLC;
    }

    private static Schema.sObjectField getCachedField(Schema.sObjectType sobjType, String qualifiedFieldName) {
        Map<String, Schema.sObjectField> fMapLC = FieldCacheLC.get(sobjType);
        if (fMapLC == null) {
            Schema.DescribeSObjectResult sDesc = sobjType.getDescribe();
            FieldSetCacheLC.put(sobjType, normalizeFieldSetMapLC(sDesc));
            FieldCacheLC.put(sobjType, fMapLC = normalizeFieldMapLC(sDesc));
        }

        // JLB - 12/12/2018 - Patch for Schema.DescribeSObjectResult.fields.getMap()
        // keys incorrectly indexing unmanaged fields by their "fully qualified" variant,
        // where the object's namespace is used in place of the field's true namespace (none).
        // Converting the resulting Schema.SObjectField token to a string reveals the correct
        // fully qualified name of the resulting token. This is used to verify that a false
        // match was not returned. Props to Mike U. for discovering this, and a few other,
        // workarounds for this annoying platform bug.
        Schema.SObjectField cachedField = fMapLC.get(qualifiedFieldName != null ? qualifiedFieldName.toLowerCase() : null);
        if (cachedField != null && '' + cachedField != qualifiedFieldName) {
            return null;
        }
        return cachedField;
    }

    /*
    static void outErr(String prefix, Exception e) {
        if (e instanceof PathExpressionException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : 'Invalid field expression: ') + e.getMessage());
        } else if (e instanceof FieldPathException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : 'Invalid field: ') + e.getMessage());
        } else if (e instanceof sObjectException) {
            outErr((String.isNotBlank(prefix) ? prefix + ': ' : '') + e.getMessage());
        } else {
            //auraErr((String.isNotBlank(prefix) ? prefix + ' unexpected error: ' : 'Unexpected error: ') + e.getMessage());
            throw e;
        }
    }
    */

    static void outErr(Exception e) {
        if (!Test.isRunningTest()) {
            AuraHandledException ae = new AuraHandledException(e.getMessage());
            ae.setMessage(e.getMessage());
            throw ae;
        } else {
            throw e;
        }
    }

    public class PathExpressionException extends Exception {}
    public class FieldPathException extends Exception {}
    //public class SOQLBuilderException extends Exception {}
    public class sObjectException extends Exception {}
    public class ReferenceException extends Exception {}

    public static void transactionalThrow() {
        SecurityModeTransactional = true;
    }

    public static void setSecurityMode(Integer newMode) {
        System.assert(newMode >= BYPASS_FLS_CRUD && newMode <= ALL_OR_NONE, 'Invalid security mode specified [' + newMode + ']');
        SecurityMode = newMode;
        resetSecurityLog(false);
    }

    //public static void setSafeSharing(RKShare.SecurityModel securityModel) {
    //    SafeSharingModel = securityModel;
    //}

    //public static void setSystemSharing(RKShare.SecurityModel securityModel) {
    //    SystemSharingModel = securityModel;
    //}

    // Forces all subsequent RKShare safe operations to execute in System mode for both CRUD/FLS and record sharing.
    // Returns a Savepoint, from right before this override, that can restore the prior settings and mode of operation 
    // via an RKShare.restore() call that is passed that Savepoint:
    public static SecuritySavepoint startSystemMode() {
        SecuritySavepoint sp = new SecuritySavepoint();
        SystemModeOverride = true;
        SecurityMode = BYPASS_FLS_CRUD;
        //SafeSharingModel = SystemSharingModel;
        return sp;
    }

    // Works like startSystemMode(), but only acts like System mode with regard to record sharing, not CRUD/FLS:
    public static SecuritySavepoint startSystemSharingMode() {
        SecuritySavepoint sp = new SecuritySavepoint();
        //SafeSharingModel = SystemSharingModel;
        return sp;
    }

    public static void restore(SecuritySavepoint state) {
        SystemModeOverride = state.systemModeFlag == true;
        SecurityMode = state.secMode;
        SecurityModeTransactional = state.transactional;
        CRUDMissMap = state.crudMiss;
        FLSMissMap = state.flsMiss;
        //SafeSharingModel = state.safeShare;
        //SystemSharingModel = state.systemShare;
    }

    public class SecuritySavepoint {
        Boolean systemModeFlag;
        Integer secMode;
        Boolean transactional;
        Map<Schema.sObjectType, Integer> crudMiss;
        Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>> flsMiss;
        //RKShare.SecurityModel safeShare;
        //RKShare.SecurityModel systemShare;

        public SecuritySavepoint() {
            this.systemModeFlag = SystemModeOverride == true;
            this.secMode = SecurityMode;
            this.transactional = SecurityModeTransactional == true;
            this.crudMiss = CRUDMissMap != null ? CRUDMissMap : new Map<Schema.sObjectType, Integer>();
            this.flsMiss = FLSMissMap != null ? FLSMissMap : new Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>>();
            //this.safeShare = SafeSharingModel != null ? SafeSharingModel : RKShare.SafeSharing();
            //this.systemShare = SystemSharingModel != null ? SystemSharingModel : RKShare.SystemSharing();
        }
    }

    public static void resetSecurityLog() {
        resetSecurityLog(false);
    }

    private static void resetSecurityLog(Boolean internalCall) {
        //if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityMode == ALL_OR_NONE_TRANSACTIONAL) {
        if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityModeTransactional == true) {
            return;
        }
        CRUDMissMap = new Map<Schema.sObjectType, Integer>();
        FLSMissMap = new Map<Schema.sObjectType, Map<Schema.sObjectField, Integer>>();
    }

    /*
    static {
        if (Test.isRunningTest()) {
            // TODO:
            setSecurityMode(ALL_OR_NONE);
        } else {
            RKQF_Settings__c sett = RKQF_Settings__c.getInstance();
            if (sett != null && sett.Security_Mode__c != null) {
                Integer iMode = sett.Security_Mode__c.intValue();
                if (sett.Security_Mode__c >= BYPASS_FLS_CRUD && sett.Security_Mode__c <= ALL_OR_NONE) {
                    setSecurityMode(iMode);
                }
            }
        }
        resetSecurityLog(false);
    }
    */

    final static Integer ACCESS_READ = 1;
    final static Integer ACCESS_CREATE = 2;
    final static Integer ACCESS_UPDATE = 4;
    final static Integer ACCESS_DELETE = 8;

    @TestVisible
    private static void logSecurityMiss(Schema.sObjectType sobjType, Integer accessType) {
        if (SecurityMode <= FILTER_FLS_CRUD) {
            return;
        }
        Integer accessBits = CRUDMissMap.get(sobjType);
        if (accessBits == null) {
            accessBits = 0;
        }
        CRUDMissMap.put(sobjType, accessBits | accessType);
    }

    @TestVisible
    private static void logSecurityMiss(Schema.sObjectType sobjType, Schema.sObjectField field, Integer accessType) {
        if (SecurityMode <= FILTER_FLS_THROW_CRUD) { //FILTER_FLS_CRUD) {
            return;
        }
        Map<Schema.sObjectField, Integer> fieldMap = FLSMissMap.get(sobjType);
        if (fieldMap == null) {
            FLSMissMap.put(sobjType, fieldMap = new Map<Schema.sObjectField, Integer>());
        }
        Integer accessBits = fieldMap.get(field);
        if (accessBits == null) {
            accessBits = 0;
        }
        fieldMap.put(field, accessBits | accessType);
    }

    public static void throwSecurityViolations() {
        throwSecurityViolations(false);
    }

    private static void throwSecurityViolations(Boolean internalCall) {
        //if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityMode == ALL_OR_NONE_TRANSACTIONAL) {
        if (SecurityMode <= FILTER_FLS_CRUD || internalCall == true && SecurityModeTransactional == true) {
            return;
        }
        String[] parts = new String[]{};
        String[] crud = new String[]{};
        for (Schema.sObjectType sobjType : CRUDMissMap.keySet()) {
            Integer accessBits = CRUDMissMap.get(sobjType);
            crud.add(sobjType + ' [' + printAccess(accessBits) + ']');
        }
        if (crud.size() > 0) {
            parts.add('Missing access for Object' + (crud.size() == 1 ? '' : 's') + ': ' + 
                String.join(crud, ', '));
        }
        for (Schema.sObjectType sobjType : FLSMissMap.keySet()) {
            Map<Schema.sObjectField, Integer> fieldMap = FLSMissMap.get(sobjType);
            String[] fls_obj = new String[]{};
            for (Schema.sObjectField field : fieldMap.keySet()) {
                Integer accessBits = fieldMap.get(field);
                fls_obj.add(field + ' [' + printAccess(accessBits) + ']');
            }
            parts.add('Missing access for Object ' + sobjType + ' field' + (fls_obj.size() == 1 ? '' : 's') + ': ' + 
                String.join(fls_obj, ', '));
        }
        if (parts.size() > 0) {
            String msg = String.join(parts, '. ');
            AuraHandledException e = new AuraHandledException(msg);
            e.setMessage(msg);
            throw e;
        }
    }

    @TestVisible
    static String printAccess(Integer accessBits) {
        String[] types = new String[]{};
        if ((accessBits & ACCESS_CREATE) > 0) {
            types.add('Create');
        }
        if ((accessBits & ACCESS_READ) > 0) {
            types.add('Read');
        }
        if ((accessBits & ACCESS_UPDATE) > 0) {
            types.add('Update');
        }
        if ((accessBits & ACCESS_DELETE) > 0) {
            types.add('Delete');
        }
        return String.join(types, ', ');
    }
}