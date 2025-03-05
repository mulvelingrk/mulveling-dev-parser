/*
*************************************************************************
CREATED BY : Mike Ulveling
CREATED DATE : April 25, 2019
DESCRIPTION : Virtual objects
ORIGINAL TICKET : All RKUX tickets
-------------------------------------------------------------------------
MOD LOG
AUTHOR: Jason Bradley
DATE : July 15, 2019
TICKET : RKDEV-10070
DESCRIPTION : Swapped code that was directly accessing the ObjectDesc
    cache (thereby circumventing the lazy-load behavior for ObjectDesc
    instances) to rely on the SchemaDesc.obj method instead. This allows
    for retrieving fields through compound paths that involve related
    objects that were NOT previously bound in the SchemaDesc.
-------------------------------------------------------------------------
*************************************************************************
*/
public with sharing class Vobj {
    // we could override this value from the default initialization, but I'm not sure if or why we'd ever want to:
    public static Boolean BindToMock = Test.isRunningTest();

    public static void upserts(Record[] recs) {
        sObject[] inserts = new sObject[]{};
        sObject[] updates = new sObject[]{};
        for (Record rec : recs) {
            if (rec.Id != null) {
                updates.add(rec.obj);
            } else {
                inserts.add(rec.obj);
            }
        }
        if (inserts.size() > 0) {
            insert inserts;
        }
        if (updates.size() > 0) {
            update updates;
        }
    }

    public virtual class Bindings {
        public virtual void define(SchemaDesc schemaDesc) { }
    }

    public static SchemaDesc getSchema(System.Type bindingsClass) {
        return new SchemaDesc(bindingsClass, null);
    }

    public static SchemaDesc getSchema(System.Type bindingsClass, Schema.sObjectType maskingPackageObject) {
        return new SchemaDesc(bindingsClass, maskingPackageObject != null ? RKSecurity.getNamespace(maskingPackageObject) : null);
    }

    public class SchemaDesc {
        public String maskingNamespace {get; private set;}
        public String maskingPrefix {get; private set;}
        private Map<String, ObjectDesc> aliasToObjDesc = new Map<String, ObjectDesc>();
        private Map<Schema.SObjectType, ObjectDesc> objTypeToObjDesc = new Map<Schema.SObjectType, ObjectDesc>();
        private Map<String, String> lcToProperObjAlias = new Map<String, String>(); // lower-case left side, proper case right side

        private PathParseErrorHandler pathErr = new PathParseErrorHandler();
        private PathParseErrorHandler storedPathErr;

        private SchemaDesc() { }

        private SchemaDesc(System.Type bindingsClass) {
            this(bindingsClass, (String) null);
        }

        private SchemaDesc(System.Type bindingsClass, String maskingNamespace) {
            setMaskingNamespace(maskingNamespace);
            if (bindingsClass != null) {
                Object o = bindingsClass.newInstance();
                Bindings binds;
                if (o instanceof Bindings) {
                    binds = (Bindings) o;
                } else {
                    throw err('The supplied Bindings Class is not an instance of Vobj.Bindings: ' + o);
                }
                
                RKSecurity.setSchema(this);
                try {
                    binds.define(this);
                } finally {
                    RKSecurity.revertSchema();
                }
            }
        }

        public void setMaskingNamespace(Schema.sObjectType maskingPackageObject) {
            setMaskingNamespace(maskingPackageObject != null ? RKSecurity.getNamespace(maskingPackageObject) : null);
        }

        private void setMaskingNamespace(String maskingNamespace) {
            if (objTypeToObjDesc.keySet().size() > 0) {
                throw err('Masking Namespace cannot be set after Object bindings have been defined');
            }
            this.maskingNamespace = maskingNamespace;
            this.maskingPrefix = maskingNamespace != null ? maskingNamespace + '__' : null;
        }

        public ObjectDesc bind(String objApi, String mockApi) {
            return bind(objApi, objApi, mockApi);
        }

        public ObjectDesc bind(String alias, String objApi, String mockApi) {
            if (String.isBlank(alias)) {
                alias = objApi;
            }
            Schema.sObjectType objType = RKSecurity.resolveSObjectTypeOrThrow(BindToMock ? mockApi : objApi);
            // Determine if an ObjectDesc has already has been registered under this alias. If no, create & register it. If yes, verify that
            // the sObjectTypes don't clash (i.e. the same alias can't be used for multiple types):
            String properAlias = lcToProperObjAlias.get(alias.toLowerCase());
            if (properAlias == null) {
                lcToProperObjAlias.put(alias.toLowerCase(), properAlias = alias);
            }
            ObjectDesc aliasDesc = aliasToObjDesc.get(properAlias);
            if (aliasDesc == null) {
                aliasToObjDesc.put(alias, aliasDesc = new ObjectDesc(this, alias, objType));
            } else if (aliasDesc.objType != objType) {
                throw err('Alias "' + alias + '" cannot be used for type ' + objType + ' because it is already in use for type ' + aliasDesc.objType);
            }
            // Determine if an ObjectDesc has already has been registered under this sObjectType. If no, create & register it. If yes, verify that
            // the aliases don't clash (i.e. the same sObjectType can't be used with multiple aliases):
            ObjectDesc objTypeDesc = objTypeToObjDesc.get(objType);
            if (objTypeDesc == null) {
                objTypeToObjDesc.put(objType, aliasDesc);
            } else if (objTypeDesc.alias != alias) {
                throw err('Alias "' + alias + '" for type ' + objType + ' clashes with prior alias definition "' + objTypeDesc.alias + '"');
            }
            return aliasDesc;
        }

        public ObjectDesc obj(Schema.sObjectType objType) {
            ObjectDesc objDesc = objTypeToObjDesc.get(objType);
            if (objDesc == null) {
                objTypeToObjDesc.put(objType, objDesc = new ObjectDesc(this, '' + objType, objType));
            }
            return objDesc;
        }

        public ObjectDesc obj(String aliasOrApi) {
            if (String.isBlank(aliasOrApi)) {
                return null;
            }
            String properAlias = lcToProperObjAlias.get(aliasOrApi.toLowerCase());
            ObjectDesc objDesc = aliasToObjDesc.get(properAlias);
            // if this object type hasn't been registered as a virtual object, then we create an ObjectDesc on the fly (no aliased fields
            // will be defined within this ObjectDesc, i.e. all entities are real-only) so that we can leverage the ObjectDesc.pathDesc 
            // method, which can traverse a mix of real and virtual entities:
            if (objDesc == null) {
                Schema.sObjectType objType = RKSecurity.resolveSObjectType(aliasOrApi);
                if (objType != null) {
                    objDesc = objTypeToObjDesc.get(objType);
                    if (objDesc == null) {
                        objTypeToObjDesc.put(objType, objDesc = new ObjectDesc(this, '' + objType, objType));
                    }
                }
            }
            if (objDesc == null) {
                throw err('No Object Type is defined under alias or api identifier: ' + aliasOrApi);
            }
            return objDesc;
        }

        // realObj - a generic JSON-serialized form of a concrete sObject record - 
        // !! Note that this method does only shallow processing on the realObj, not deep:
        public void applyAliasesShallow(Schema.sObjectType objType, Map<String, Object> realObj) {
            // JLB - RKDEV-10070 - Refer to comment below (lines 887-892) for justification for this modification.
            //ObjectDesc objDesc = objTypeToObjDesc.get(objType);
            ObjectDesc objDesc = obj(objType);
            if (objDesc != null) {
                for (String realField : realObj.keySet()) {
                    String properRealField = objDesc.lcToProperApi.get(realField.toLowerCase());
                    if (properRealField != null) {
                        EntityDesc entity = objDesc.apiToEntity.get(properRealField);
                        realObj.put(entity.alias, realObj.get(realField));
                    }
                }
            }
        }
        
        // Resolves any path of mixed aliases and real fields, no matter the root object type - even if root hasn't been defined as a 
        // virtual object. All necessary metadata for a path is contained within the returned structure. The path may terminate in a
        // Field, Child Relationship, or a Parent Relationship:
        public PathDesc path(Schema.sObjectType objType, String aliasedPath) {
            return obj(objType).path(aliasedPath);
        }

        public PathDesc path(String objType, String aliasedPath) {
            return obj(objType).path(aliasedPath);
        }

        public PathDesc path(String rootedEntityPath) {
            List<String[]> paths = splitPathsToParts(rootedEntityPath);
            if (paths.isEmpty()) {
//                throw err('Path cannot be empty');
                pathErr.reset(rootedEntityPath, true, null);
                pathErr.emptyPath();
                return null;
            }
            String[] parts = paths[0];
            //ObjectDesc rootObjDesc = obj(parts.remove(0));
            // note we replicate most of the this.obj(String) method here because we need custom path error handling:
            String objName = parts[0]; //parts.remove(0);
            ObjectDesc objDesc;
            String objProperAlias = lcToProperObjAlias.get(objName.toLowerCase());
            if (objProperAlias != null) {
                objDesc = aliasToObjDesc.get(objProperAlias);
            } else {
                // if this object type hasn't been registered as a virtual object, then we create an ObjectDesc on the fly (no aliased 
                // fields will be defined within this ObjectDesc, i.e. all entities are real-only) so that we can leverage the 
                // ObjectDesc.pathDesc method, which can traverse a mix of real and virtual entities:
                Schema.sObjectType objType = RKSecurity.resolveSObjectType(objName);
                if (objType != null) {
                    objDesc = objTypeToObjDesc.get(objType);
                    if (objDesc == null) {
                        objTypeToObjDesc.put(objType, objDesc = new ObjectDesc(this, '' + objType, objType));
                    }
                }
            }
            if (objDesc == null) {
                throw err('No Object Type is defined under alias or api identifier: ' + objName);
            }
            if (parts.size() > 0) {
                return objDesc.path(String.join(parts, '.'), true);
            } else {
                throw err('Expected path after root ' + objDesc.describe());
            }
        }

        public EntityDesc entity(String rootedEntityPath) {
            List<String[]> paths = splitPathsToParts(rootedEntityPath);
            if (paths.isEmpty()) {
                //throw err('Path cannot be empty');
                pathErr.reset(rootedEntityPath, true, null);
                pathErr.emptyPath();
                return null;
            }
            String[] parts = paths[0];
            //ObjectDesc rootObjDesc = obj(parts.remove(0));
            // note we replicate most of the this.obj(String) method here because we need custom path error handling:
            String objName = parts[0]; //parts.remove(0);
            ObjectDesc objDesc;
            String objProperAlias = lcToProperObjAlias.get(objName.toLowerCase());
            if (objProperAlias != null) {
                objDesc = aliasToObjDesc.get(objProperAlias);
            } else {
                // if this object type hasn't been registered as a virtual object, then we create an ObjectDesc on the fly (no aliased 
                // fields will be defined within this ObjectDesc, i.e. all entities are real-only) so that we can leverage the 
                // ObjectDesc.pathDesc method, which can traverse a mix of real and virtual entities:
                Schema.sObjectType objType = RKSecurity.resolveSObjectType(objName);
                if (objType != null) {
                    objDesc = objTypeToObjDesc.get(objType);
                    if (objDesc == null) {
                        objTypeToObjDesc.put(objType, objDesc = new ObjectDesc(this, '' + objType, objType));
                    }
                }
            }
            if (objDesc == null) {
                //throw err('No Object Type is defined under alias or api identifier: ' + objName);
                pathErr.reset(rootedEntityPath, true, null);
                pathErr.rawPath = rootedEntityPath;
                pathErr.rawRoot = objName;
                pathErr.rootObj();
            }
            if (parts.size() > 0) {
                PathDesc pathDesc = objDesc.path(rootedEntityPath, true);
                return pathDesc.entity;
            } else {
                return objDesc;
            }
        }

        public EntityDesc childRel(String rootedEntityPath) {
            EntityDesc entity = entity(rootedEntityPath);
            if (!entity.isChildRel) {
                throw err('Expected path ' + rootedEntityPath + ' to resolve to a Child Relationship; got: ' + entity.describe());
            }
            return entity;
        }

        public Record record(sObject obj) {
            if (obj == null) {
                //throw err('Cannot create a Record from null');
                return null;
            }
            return new Record(obj(obj.getSObjectType()), obj);
        }

        // field reads are protected by FLS security:
        public Record safeRecord(sObject obj) {
            if (obj == null) {
                //throw err('Cannot create a Record from null');
                return null;
            }
            Record rec = new Record(obj(obj.getSObjectType()), obj);
            rec.safeReadMode = true;
            return rec;
        }

        public Record systemRecord(sObject obj) {
            if (obj == null) {
                //throw err('Cannot create a Record from null');
                return null;
            }
            Record rec = new Record(obj(obj.getSObjectType()), obj);
            rec.safeReadMode = false;
            return rec;
        }

        // TODO: deprecated; use safeRecord or systemRecord instead:
        // returns a Record of the 1st sObject element from an array:
        public Record record(sObject[] objArray) {
            if (objArray == null || objArray.isEmpty()) {
                //throw err('Cannot create a Record from null');
                return null;
            }
            return new Record(obj(objArray[0].getSObjectType()), objArray[0]);
        }

        public Record[] records(sObject[] objArray) {
            Record[] records = new Record[]{};
            if (objArray != null) {
                for (sObject obj : objArray) {
                    records.add(new Record(this, obj));
                }
            }
            return records;
        }

        // TODO: deprecate; this method sucks because you lose scope for `:varName` params:
        public Record[] query(String soql) {
            Record[] recs = new Record[]{};
            ObjectDesc objDesc;
            for (sObject obj : Database.query(soql)) {
                // query results guaranteed to be homogenous, so we need only calc the ObjectDesc one time:
                if (objDesc == null) {
                    objDesc = obj(obj.getSObjectType());
                }
                recs.add(new Record(objDesc, obj));
            }
            return recs;
        }

        public void setPathErrorHandling(PathParseErrorHandler alternateHandler) {
            this.storedPathErr = pathErr;
            this.pathErr = alternateHandler;
        }

        public void revertPathErrorHandling() {
            if (storedPathErr == null) {
                this.pathErr = new PathParseErrorHandler();
            } else {
                this.pathErr = storedPathErr;
            }
        }
    }

    // For serializing entity metadata to JSON
    public class EntitySet {
        SchemaDesc schemaDesc;
        // strict-form path (fully namespace qualified, proper case) to the PathDesc for each entity in this set:
        Map<Schema.sObjectType, Map<String, PathDesc>> objToStrictToPath = new Map<Schema.sObjectType, Map<String, PathDesc>>();

        public EntitySet add(EntitySet arg) {
            if (schemaDesc != arg.schemaDesc) {
                throw err('Can\'t merge Entity Sets from different Schemas');
            }
            for(Schema.sObjectType objType : arg.objToStrictToPath.keySet()) {
                Map<String, PathDesc> strictToPath = objToStrictToPath.get(objType);
                if (strictToPath == null) {
                    objToStrictToPath.put(objType, strictToPath = new Map<String, PathDesc>());
                }
                strictToPath.putAll(arg.objToStrictToPath.get(objType));
            }
            return this;
        }

        public EntitySet addIntermediates() {
            for (Schema.sObjectType rootType : objToStrictToPath.keySet()) {
                ObjectDesc rootDesc = schemaDesc.obj(rootType);
                Map<String, PathDesc> strictToPath = objToStrictToPath.get(rootType);
                for (PathDesc path : strictToPath.values()) {
                    Integer penIndex = path.parts.size() - 2;
                    if (penIndex < 0) {
                        continue;
                    }
                    String partialPath;
                    for (Integer i=0; i <= penIndex; i++) {
                        EntityDesc part = path.parts[i];
                        if (partialPath == null) {
                            partialPath = part.api;
                        } else {
                            partialPath += '.' + part.api;
                        }
                        if (!strictToPath.containsKey(partialPath)) {
                            strictToPath.put(partialPath, rootDesc.path(partialPath));
                        }
                    }
                }
            }
            return this;
        }

        public Map<String, Object> toJSONMap() {
            Map<String, ObjectSer> aliasToObjSer = new Map<String, ObjectSer>();
            // strict path-to-holder to the ObjectSer built specifically for that holder:
            Map<String, ObjectSer> holderObjPool = new Map<String, ObjectSer>();
            for (Schema.sObjectType objType : objToStrictToPath.keySet()) {
                ObjectDesc objDesc = schemaDesc.obj(objType);
                ObjectSer objSer = new ObjectSer();
                objSer.key = getKey(schemaDesc, objDesc);
                objSer.strict = objDesc.api;
                objSer.real = getRealApi(schemaDesc, objDesc);
                aliasToObjSer.put(objSer.key, objSer);
                Map<String, PathDesc> pathsByStrict = objToStrictToPath.get(objType);
                for (String strictPath : pathsByStrict.keySet()) {
                    PathDesc path = pathsByStrict.get(strictPath);
                    Integer partsLen = path.parts.size();
                    PathSer pathSer = new PathSer(path);
                    objSer.pathMap.put(pathSer.key, pathSer);
                    if (partsLen > 1) {
                        PartSer priorPartSer;
                        for (Integer i=0; i < partsLen; i++) {
                            EntityDesc entity = path.parts[i];
                            ObjectSer holderObjSer;
                            if (i == 0) {
                                holderObjSer = objSer;
                            } else {
                                String holderStrictPath = objSer.strict + '.' + (priorPartSer.strictPath != null ? priorPartSer.strictPath : priorPartSer.strict);
                                holderObjSer = holderObjPool.get(holderStrictPath);
                                if (holderObjSer == null) {
                                    ObjectDesc holderObj = entity.objDesc;
                                    holderObjPool.put(holderStrictPath, holderObjSer = new ObjectSer());
                                    holderObjSer.key = getKey(schemaDesc, holderObj);
                                    holderObjSer.strict = holderObj.api;
                                    holderObjSer.real = getRealApi(schemaDesc, holderObj);
                                }
                            }

                            String key = getKey(schemaDesc, entity);
                            PartSer partSer = holderObjSer.partMap.get(key);
                            if (partSer == null) {
                                holderObjSer.partMap.put(key, partSer = new PartSer());
                                partSer.key = key;
                                partSer.strict = entity.api;
                                partSer.real = getRealApi(schemaDesc, entity);
                                if (i > 0) {
                                    // prior part may have a null strictPath/realPath if it is the head part of the path:
                                    partSer.strictPath = (priorPartSer.strictPath != null ? priorPartSer.strictPath : priorPartSer.strict) + '.' + partSer.strict;
                                    partSer.realPath = (priorPartSer.realPath != null ? priorPartSer.realPath : priorPartSer.real) + '.' + partSer.real;
                                    priorPartSer.nextPartMap.put(key, partSer);
                                }
                            }
                            priorPartSer = partSer;
                        }
                    }
                }
            }

            // 2nd pass:
            Map<String, Object> schemaJSON = new Map<String, Object>();
            for (ObjectSer obj : aliasToObjSer.values()) {
                Map<String, Object> objJSON = new Map<String, Object>();
                schemaJSON.put(obj.key, objJSON);
                for (PartSer rootPart : obj.partMap.values()) {
                    PartSer[] stack = new PartSer[]{ rootPart };
                    Integer top = 0;
                    do {
                        PartSer currPart = stack.remove(top--);
                        for (PartSer nextPart : currPart.nextPartMap.values()) {
                            top++;
                            stack.add(nextPart);
                            currPart.json.put(nextPart.key, nextPart.json);
                        }
                        currPart.json.put('_strict', currPart.strict);
                        if (currPart.strictPath != null) {
                            currPart.json.put('_strictPath', currPart.strictPath);
                        }
                        currPart.json.put('_real', currPart.real);
                        if (currPart.realPath != null) {
                            currPart.json.put('_realPath', currPart.realPath);
                        }
                    } while (top > -1);
                    objJSON.put(rootPart.key, rootPart.json);
                }
                for (PathSer path : obj.pathMap.values()) {
                    objJSON.put(path.key, new Map<String, Object>{
                        '_strict' => path.strict,
                        '_real' => path.real
                    });
                }
                objJSON.put('_strict', obj.strict);
                objJSON.put('_real', obj.real);
            }
            // TODO: make not-pretty for efficiency:
            //return JSON.serializePretty(schemaJSON);
            return schemaJSON;
        }
    }

    static String getKey(SchemaDesc schemaDesc, EntityDesc entity) {
        if (entity.alias != null) {
            return entity.alias;
        }
        return getRealApi(schemaDesc, entity);
    }

    static String getRealApi(SchemaDesc schemaDesc, EntityDesc entity) {
        if (schemaDesc.maskingPrefix != null) {
            if (entity.api.startsWith(schemaDesc.maskingPrefix)) {
                String strippedApi = entity.api.substring(schemaDesc.maskingPrefix.length(), entity.api.length());
                if (strippedApi != 'c' && strippedApi != 'r') {
                    return strippedApi;
                }
            }
        }
        return entity.api;
    }

    class ObjectSer {
        String key;
        String strict;
        String real;
        // 'foo' => {_strict: 'ns__Foo__r', _real: 'Foo__r'}, 
        //     'bar' => {_strict: 'ns__Bar__r', _real: 'Bar__r', _strictPath: 'ns__Foo__c.ns__Bar__r', _realPath: 'Foo__c.Bar__r'}, 
        //         'bazId' => {_strict: 'ns__Baz__c', _real: 'Baz__c', _strictPath: 'ns__Foo__c.ns__Bar__r.ns__Baz__c', _realPath: 'Foo__c.Bar__r.Baz__c'}
        Map<String, PartSer> partMap = new Map<String, PartSer>();
        // 'foo.bar.bazId' => {_strict: 'ns__Foo__c.ns__Bar__r.ns__Baz__c', _real: 'Foo__c.Bar__r.Baz__c'} 
        Map<String, PathSer> pathMap = new Map<String, PathSer>();
    }

    class PartSer {
        String key;
        String strict;
        String strictPath;
        String real;
        String realPath;
        Map<String, PartSer> nextPartMap = new Map<String, PartSer>(); // if null then this is a terminating entity

        Map<String, Object> json = new Map<String, Object>();
    }

    class PathSer {
        String key;
        String strict;
        String real;

        PathSer(PathDesc path) {
            this.key = path.key;
            this.strict = path.strict;
            this.real = path.real;
        }
    }

    public virtual class EntityDesc {
        public SchemaDesc schemaDesc {get; private set;} // host Schema, populated for Object entities only
        public ObjectDesc objDesc {get; private set;} // host Object, populated for non-Object entities only
        public String alias {get; private set;} // proper case
        public String api {get; private set;} // proper case, fully qualified

        public Boolean isObject {get; private set;}
        public Boolean isField {get; private set;}
        public Boolean isChildRel {get; private set;}
        public Boolean isParentRel {get; private set;}
        
        public Boolean isReal {get{ return alias == null; }}
        public Boolean isVirtual {get{ return alias != null; }}
        
        public Schema.sObjectType objType {get; private set;}
        public Schema.sObjectField field {get; private set;}
        public Schema.DescribeFieldResult fieldDesc {get; private set;}
        public Schema.ChildRelationship childRel {get; private set;}

        public Boolean accessible {get{
            if (isObject) {
                return this.objType.getDescribe().isAccessible();
            } else if (isField) {
                return fieldDesc.isAccessible();
            } else if (isParentRel) {
                // use the parent lookup field to determine accessibility:
                return fieldDesc.isAccessible();
            } else if (isChildRel) {
                // use the lookup field on the child side of the child rel to determine accessibility:
                return childRel.getField().getDescribe().isAccessible();
            }
            return null;
        }}

        public Boolean createable {get{
            if (isObject) {
                return this.objType.getDescribe().isCreateable();
            } else if (isField) {
                return fieldDesc.isCreateable();
            }
            return null;
        }}

        public Boolean updateable {get{
            if (isObject) {
                return this.objType.getDescribe().isUpdateable();
            } else if (isField) {
                return fieldDesc.isUpdateable();
            }
            return null;
        }}

        public Boolean isNumberField {get{
            return isField && (fieldDesc.getSOAPType() == Schema.SOAPType.DOUBLE || fieldDesc.getSOAPType() == Schema.SOAPType.INTEGER);
        }}

        // Creates an Object entity on the given host Schema:
        private EntityDesc(SchemaDesc schemaDesc, Schema.sObjectType objType) {
            this.schemaDesc = schemaDesc;
            this.api = '' + objType;
            this.isObject = true;
            this.isField = false;
            this.isChildRel = false;
            this.isParentRel = false;
            this.objType = objType;
        }

        // Creates a Field entity on the given host Object entity:
        private EntityDesc(ObjectDesc objDesc, String alias, Schema.sObjectField field) {
            this.schemaDesc = objDesc.schemaDesc;
            this.objDesc = objDesc;
            this.alias = alias;
            this.api = '' + field;
            this.isObject = false;
            this.isField = false;
            this.isChildRel = false;
            this.isParentRel = false;
            this.objType = objDesc.objType;
            this.field = field;
            this.fieldDesc = field != null ? field.getDescribe() : null;
        }

        // Creates a "real" (non-aliased) Field/ChildRel/ParentRel entity on the given host Object entity:
        private EntityDesc(ObjectDesc objDesc, RealDesc realDesc) {
            this.schemaDesc = objDesc.schemaDesc;
            this.objDesc = objDesc;
            this.alias = null;
            this.api = realDesc.api;
            this.isObject = false;
            this.isField = false;
            this.isChildRel = false;
            this.isParentRel = false;
            if (realDesc.childRel != null) {
                this.isChildRel = true;
                this.childRel = realDesc.childRel;
            } else if (realDesc.parentRelApi != null) {
                this.isParentRel = true;
                //this.parentRelApi = realDesc.parentRelApi;
            } else if (realDesc.field != null) {
                this.isField = true;
            }
            this.objType = objDesc.objType;
            //this.realDesc = realDesc;
            this.field = realDesc.field;
            this.fieldDesc = realDesc.fieldDesc;
        }

        public override String toString() {
            return api;
        }

        public String describe() {
            if (isField) {
                return 'Field ' + api + (alias != null ? ' [alias: ' + alias + ']' : '');
            } else if (isParentRel) {
                return 'Parent Relationship ' + api + (alias != null ? ' [alias: ' + alias + ']' : '');
            } else if (isChildRel) {
                return 'Child Relationship ' + api + (alias != null ? ' [alias: ' + alias + ']' : '');
            } else if (isObject) {
                return 'Object ' + api + (alias != null ? ' [alias: ' + alias + ']' : '');
            }
            return 'Undefined Entity';
        }
    }

    public class ObjectDesc extends EntityDesc {
        private Map<String, EntityDesc> apiToEntity = new Map<String, EntityDesc>(); // proper cases left sides
        private Map<String, EntityDesc> aliasToEntity = new Map<String, EntityDesc>(); // proper case left side
        private Map<String, String> lcToProperApi = new Map<String, String>(); // lower-case left side, proper case right side
        private Map<String, String> lcToProperAlias = new Map<String, String>(); // lower-case left side, proper case right side

        // lower-case'd, space-removed aliased path to a compiled PathDesc:
        private Map<String, PathDesc> pathCache = new Map<String, PathDesc>();

        ObjectDesc(SchemaDesc schemaDesc, String alias, Schema.sObjectType objType) {
            super(schemaDesc, objType);
            this.alias = alias;
        }

        public ObjectDesc bind(String[] aliasFields) {
            for (Integer i=0; i < aliasFields.size() - 1; i += 2) {
                String alias = aliasFields[i];
                String field = aliasFields[i + 1];
                bind(alias, field);
            }
            return this;
        }

        public ObjectDesc bindWithMock(String[] aliasFieldMocks) {
            for (Integer i=0; i < aliasFieldMocks.size() - 2; i += 3) {
                String alias = aliasFieldMocks[i];
                String field = aliasFieldMocks[i + 1];
                String mock = aliasFieldMocks[i + 2];
                bind(alias, BindToMock ? mock : field);
            }
            return this;
        }

        public ObjectDesc bind(String alias, String entityApi) {
            if (String.isBlank(alias)) {
                alias = entityApi;
            } else if (String.isBlank(entityApi)) {
                entityApi = alias;
            }
            if (String.isBlank(entityApi)) {
                throw err('Field api cannot be blank');
            }

            // determine if entity api name is a field, parent rel, or child rel:
            EntityDesc entity;
            Schema.sObjectField field = RKSecurity.resolveField(objType, entityApi);

            // if we resolved as a field:
            if (field != null) {
                entity = new EntityDesc(this, alias, field);
                entity.isField = true;
                entity.api = entity.fieldDesc.getName();
            } else {
                Schema.DescribeFieldResult invalidParentLkpDesc;
                // else try to resolve as a custom parent lookup relationship:
                if (entityApi.endsWithIgnoreCase('__r')) {
                    field = RKSecurity.resolveField(objType, entityApi.replaceFirst('(?i)__r$', '__c'));
                    if (field != null) {
                        //fieldDesc = field.getDescribe();
                        entity = new EntityDesc(this, alias, field);
                        entity.isParentRel = true;
                        if (entity.fieldDesc.getType() == Schema.DisplayType.REFERENCE) {
                            entity.api = entity.fieldDesc.getName().replaceFirst('(?i)__c$', '__r');
                        // else parent relationship is invalid for non-reference field type:
                        } else {
                            invalidParentLkpDesc = entity.fieldDesc;
                            entity = null;
                        }
                    }
                // else try to resolve as a standard parent lookup relationship:
                } else if (!entityApi.endsWithIgnoreCase('__c') && !entityApi.endsWithIgnoreCase('Id')) {
                    field = RKSecurity.resolveField(objType, entityApi + 'Id');
                    if (field != null) {
                        entity = new EntityDesc(this, alias, field);
                        entity.isParentRel = true;
                        entity.api = entity.fieldDesc.getName().replaceFirst('(?i)Id$', '');
                    }
                }

                // and as a final resort, try to resolve as a child relationship:
                if (entity == null) {
                    //Schema.ChildRelationship childRel = RKSecurity.resolveChildRel(objType, entityApi);
                    Schema.ChildRelationship childRel = RKSecurity.resolveChildRelFromParent(objType, entityApi);
                    if (childRel != null) {
                        entity = new EntityDesc(this, alias, null);
                        entity.isChildRel = true;
                        entity.childRel = childRel;
                        entity.api = childRel.getRelationshipName();
                    }
                    
                    if (entity == null) {
                        if (invalidParentLkpDesc != null) {
                            throw err('Parent relationship ' + entityApi + ' is invalid for ' + invalidParentLkpDesc.getType().name() + 
                                ' field ' + invalidParentLkpDesc.getName());
                        } else {
                            throw err('Could not resolve entity ' + entityApi + ' on object ' + objType + ' as a field, parent relationship, or child relationship');
                        }
                    }
                }
            }

            EntityDesc priorEntity = apiToEntity.put(entity.api, entity);
            if (priorEntity == null) {
                apiToEntity.put(entity.api, entity);
                lcToProperApi.put(entity.api.toLowerCase(), entity.api);
            } else if (priorEntity.alias != entity.alias) {
                // we allow a late-bind to an alias if the entity was mapped but not previously aliased:
                if (priorEntity.alias != null || entity.alias == null) {
                    throw err(entity.describe() + ' cannot be redundantly bound to aliases ' + priorEntity.alias + ' and ' + entity.alias);
                }
            }

            String properAlias = lcToProperAlias.get(entity.alias.toLowerCase());
            if (properAlias == null) {
                lcToProperAlias.put(entity.alias.toLowerCase(), properAlias = entity.alias);
            }
            priorEntity = aliasToEntity.put(properAlias, entity);
            if (priorEntity != null && priorEntity.api != entity.api) {
                throw err('Alias ' + entity.alias + ' cannot be rebound from ' + priorEntity.describe() + ' to ' + entity.describe());
            }

            return this;
        }

        public PathDesc path(String aliasedPath) {
            return path(aliasedPath, false);
        }

        private PathDesc path(String aliasedPath, Boolean isObjRootedPath) {
            String requestedPath = aliasedPath;
            PathDesc cachedPath = pathCache.get(requestedPath);
            if (cachedPath != null) {
                return cachedPath;
            }
            // TODO: make this more efficient:
            //aliasedPath = aliasedPath.replaceAll('\\s++', '');

            PathDesc pathDesc = new PathDesc(this);
            pathDesc.sourcePath = aliasedPath;
            // TODO: make this more efficient:
            //String[] parts = aliasedPath.trim().split('\\s*+\\.\\s*+');
            List<String[]> paths = splitPathsToParts(aliasedPath);
            if (paths.isEmpty()) {
                PathParseErrorHandler pe = schemaDesc.pathErr;
                pe.reset(aliasedPath, isObjRootedPath, this);
                pe.emptyPath();
            }
            String[] parts = paths.size() > 0 ? paths[0] : null;
            Integer len = parts != null ? parts.size() : 0;
            if (len == 0) {
                PathParseErrorHandler pe = schemaDesc.pathErr;
                pe.reset(aliasedPath, isObjRootedPath, this);
                pe.emptyPath();
                return null;
            }
            String rootObjPart;
            if (isObjRootedPath == true) {
                rootObjPart = parts[0]; //parts.remove(0);
                if (len == 1) { //.isEmpty()) {
                    PathParseErrorHandler pe = schemaDesc.pathErr;
                    pe.reset(aliasedPath, isObjRootedPath, this);
                    pe.emptyPathAfterRootObj();
                    return null;
                }
            }
            EntityDesc[] entities = pathDesc.parts = new EntityDesc[]{}; // record each entity along the entire path
            String[] strict = new String[]{};
            Schema.sObjectType holderType = this.objType;
            for (Integer i=isObjRootedPath == true ? 1 : 0; i < len - 1; i++) {
                // JLB - RKDEV-10070 - Refer to comment below (lines 887-892) for justification for this modification.
                //ObjectDesc holderObjDesc = schemaDesc.objTypeToObjDesc.get(holderType);
                ObjectDesc holderObjDesc = schemaDesc.obj(holderType);
                String properAlias;
                if (holderObjDesc != null) {
                    properAlias = holderObjDesc.lcToProperAlias.get(parts[i].toLowerCase());
                }
                // if this part is aliased, then get its EntityDesc and resolve from that:
                if (properAlias != null) {
                    EntityDesc entity = holderObjDesc.aliasToEntity.get(properAlias);
                    if (entity.isParentRel) {
                        // TODO: better handling of polymorphic lookups...
                        holderType = entity.fieldDesc.getReferenceTo()[0];
                        strict.add(entity.api);
                        entities.add(entity);
                        continue;
                    } else {
                        //throw err('Alias ' + parts[i] + ' in path ' + aliasedPath + ' is not a Parent Relationship (' + entity.describe() + ')');
                        PathParseErrorHandler pe = schemaDesc.pathErr;
                        pe.reset(aliasedPath, isObjRootedPath, this);
                        pe.initPart(i, holderObjDesc);
                        pe.part.properAlias = properAlias;
                        pe.part.entity = entity;
                        pe.interiorPart();
                    }
                // else this part must represent a "real" parent relationship:
                } else {
                    String realPart = parts[i];
                    RealDesc resolved = resolveRealPart(holderType, realPart);
                    if (resolved.unresolved || resolved.parentRelApi == null) {
                        PathParseErrorHandler pe = schemaDesc.pathErr;
                        pe.reset(aliasedPath, isObjRootedPath, this);
                        pe.initPart(i, holderObjDesc);
                        pe.part.real = resolved;
                        pe.interiorPart();
                    }
                    /*
                    if (resolved.unresolved) {
                        if (resolved.invalidParentRelType != null) {
                            throw err('Real part ' + realPart + ' in path ' + aliasedPath + ' has the wrong underlying Field type [' + resolved.fieldDesc.getType().name() + '] for a Parent Relationship');
                        }
                        throw err('Real part ' + realPart + ' in path ' + aliasedPath + ' is not a valid Field, Child Relationship, or Parent Relationship');
                    } else if (resolved.parentRelApi == null) {
                        throw err('Real part ' + realPart + ' in path ' + aliasedPath + ' was expected to be a Parent Relationship; got ' + (resolved.childRel != null ? 'Child Relationship' : 'Field'));
                    }
                    */
                    // TODO: better handling of polymorphic lookups...
                    holderType = resolved.fieldDesc.getReferenceTo()[0];
                    strict.add(resolved.api);
                    //entities.add(new EntityDesc(holderObjDesc, resolved));
                    entities.add(realPartToEntity(holderObjDesc, resolved));
                }
            }

            // JLB - RKDEV-10070 - Ran into an issue when using a field on a related object, where that related object had not been previously referenced through the SchemaDesc.
            // SchemaDesc's internal registry appears to be lazy-loading sObjectTypes, so this original line (where it pulls directly from that registry) is odd.
            // Swapped for SchemaDesc.obj call for to hook into that lazy-loaded behavior, which may have been what was intended all along anyways.
            //ObjectDesc holderObjDesc = schemaDesc.objTypeToObjDesc.get(holderType);
            ObjectDesc holderObjDesc = schemaDesc.obj(holderType);
            String termPart = parts[len - 1];
            String properAlias;
            if (holderObjDesc != null) {
                properAlias = holderObjDesc.lcToProperAlias.get(termPart.toLowerCase());
            }
            // if the terminating part is aliased, then use its EntityDesc to resolve its real field:
            if (properAlias != null) {
                pathDesc.entity = holderObjDesc.aliasToEntity.get(properAlias);
                strict.add(pathDesc.entity.api);
            // else terminating part must resolve to a valid real field:
            } else {
                RealDesc termReal = resolveRealPart(holderType, termPart);
                if (termReal.unresolved) {
                    PathParseErrorHandler pe = schemaDesc.pathErr;
                    pe.reset(aliasedPath, isObjRootedPath, this);
                    pe.initPart(len - 1, holderObjDesc);
                    pe.part.real = termReal;
                    pe.terminatingPart();
                    /*
                    String prefix = len == 1 ? 'Real path ' + termPart : 'Real part ' + termPart + ' terminating path ' + aliasedPath;
                    if (termReal.invalidParentRelType != null) {
                        throw err(prefix + ' has the wrong underlying Field type [' + termReal.fieldDesc.getType().name() + '] for a Parent Relationship');
                    }
                    throw err(prefix + ' is not a valid Field, Child Relationship, or Parent Relationship');
                    */
                } else {
                    //System.assert(holderObjDesc != null, 'Null holder: ' + holderType + '::' + termPart + '::' + aliasedPath);
                    pathDesc.entity = realPartToEntity(holderObjDesc, termReal);
                    strict.add(termReal.api);
                }
            }
            entities.add(pathDesc.entity);
            //pathDesc.real = String.join(real, '.');
            pathDesc.strict = String.join(strict, '.');
            //pathDesc.head = RKSecurity.getPathMeta(objType, pathDesc.real);
            pathDesc.head = entities[0];

            //pathCache.put(aliasedPath.toLowerCase(), pathDesc);
            pathCache.put(requestedPath, pathDesc);
            return pathDesc;
        }

        public String selectTouched() {
            String[] sels = new String[]{};
            for (EntityDesc entity : apiToEntity.values()) {
                if (entity.isField) {
                    sels.add(entity.api);
                }
            }
            return String.join(sels, ',');
        }

        public String safeSelects(String delimitedEntityPaths) {
            return selects(delimitedEntityPaths, true);
        }

        public String selects(String delimitedEntityPaths) {
            return selects(delimitedEntityPaths, false);
        }

        public String selects(String delimitedEntityPaths, Boolean safeAccess) {
            if (safeAccess == true) {
                RKSecurity.resetSecurityLog(true);
            }
            Set<String> sels = new Set<String>();
            Integer removedCount = 0;
            try {
                for (String entityPath : splitPaths(delimitedEntityPaths)) {
                    PathDesc pathDesc = this.path(entityPath);
                    if (safeAccess != true || pathDesc.assertReadable) {
                        sels.add(pathDesc.strict);
                    } else {
                        removedCount++;
                    }
                }
                sels.remove(null);
                if (sels.size() == 0) {
                    return 'Id';
                }
            } finally {
                if (safeAccess == true) {
                    RKSecurity.throwSecurityViolations(true);
                }
                return String.join(new List<String>(sels), ',');
            }
            return null; // unreachable
        }

        public EntitySet entitySet(String delimitedEntityPaths) {
            EntitySet entities = new EntitySet();
            entities.schemaDesc = schemaDesc;
            Map<String, PathDesc> strictToPath;
            entities.objToStrictToPath.put(objType, strictToPath = new Map<String, PathDesc>());
            for (String entityPath : splitPaths(delimitedEntityPaths)) {
                PathDesc path = this.path(entityPath);
                strictToPath.put(path.strict, path);
            }
            return entities;
        }

        public EntityDesc entity(String entityPath) {
            // TODO: make this more efficient:
            entityPath = entityPath.trim().replaceAll('\\s++', '');
            String[] parts = entityPath.split('\\s++');
            PathDesc pathDesc = this.path(String.join(parts, '.'));
            return pathDesc.entity;
        }

        public EntityDesc childRel(String entityPath) {
            EntityDesc entity = entity(entityPath);
            if (!entity.isChildRel) {
                throw err('Expected path ' + entityPath + ' to resolve to a Child Relationship; got: ' + entity.describe());
            }
            return entity;
        }

        public sObject newSObject() {
            return objType.newSObject();
        }

        public sObject newSObject(Id idVal) {
            return objType.newSObject(idVal);
        }

        public sObject newSObject(Id idVal, Map<String, Object> fieldValues) {
            sObject sobj = newSObject(fieldValues);
            sobj.put('Id', idVal);
            return sobj;
        }

        public sObject newSObject(Map<String, Object> fieldValues) {
            Object oid;
            for (String key : fieldValues.keySet()) {
                if (key == 'Id') {
                    oid = fieldValues.get(key);
                }
            }
            sObject sobj = objType.newSObject();
            Id idVal;
            for (String key : fieldValues.keySet()) {
                if (key == 'Id') {
                    idVal = (Id) fieldValues.get(key);
                    continue;
                }
                PathDesc path = this.path(key);
                if (!path.entity.isField) {
                    throw err('Expected a field to set sObject value, got: ' + path.entity.describe());
                } else if (path.isCompound) {
                    throw err('Cannot use compound path to set sObject value: ' + path.strict);
                }
                put(this, sobj, path, fieldValues.get(key));
            }
            // set Id last - avoids sObject bug that disallows setting any Master-Detail field value after setting an Id:
            if (idVal != null) {
                sobj.put('Id', idVal);
            }
            return sobj;
        }

        public Record newRecord() {
            return new Record(this, objType.newSObject());
        }

        public Record newRecord(Id idVal) {
            return new Record(this, objType.newSObject(idVal));
        }

        public Record newRecord(Id idVal, Map<String, Object> fieldValues) {
            Record rec = new Record(this, newSObject(fieldValues));
            rec.obj.put('Id', idVal);
            return rec;
        }

        public Record newRecord(Map<String, Object> fieldValues) {
            return new Record(this, newSObject(fieldValues));
        }

        public Schema.RecordTypeInfo getRecordTypeInfo(String developerName) {
            RKSecurity.setSchema(this.schemaDesc);
            try {
                return RKSecurity.resolveRecordType(objType, developerName);
            } finally {
                RKSecurity.revertSchema();
            }
        }

        public Schema.FieldSet getFieldSet(String developerName) {
            RKSecurity.setSchema(this.schemaDesc);
            try {
                return RKSecurity.resolveFieldSet(objType, developerName);
            } finally {
                RKSecurity.revertSchema();
            }
        }
    }

    private static void put(ObjectDesc objDesc, sObject sobj, PathDesc path, Object oVal) {
        Schema.DescribeFieldResult fieldDesc = path.entity.fieldDesc;
        String putName = fieldDesc.getName();
        if (oVal == null) {
            sobj.put(putName, null);
            return;
        }
        Schema.SOAPType soapType = fieldDesc.getSOAPType();
        Schema.DisplayType displayType = fieldDesc.getType();
        Object putVal;
        if (soapType == Schema.SOAPType.STRING) {
            putVal = String.valueOf(oVal);
        } else if (displayType == Schema.DisplayType.REFERENCE) {
            Id idVal = null;
            if (oVal instanceof Id) {
                idVal = (Id) oVal;
            } else if (oVal instanceof String) {
                try {
                    idVal = Id.valueOf((String) oVal);
                } catch (Exception ignore) {}
            }
            if (idVal == null) {
                throw err('Non-Id value is incompatible with Lookup field ' + path.strict + ': ' + oVal);
            }
            Boolean lkpMatch = false;
            for (Schema.sObjectType lkpType : fieldDesc.getReferenceTo()) {
                if (lkpType == idVal.getSObjectType()) {
                    lkpMatch = true;
                    break;
                }
            }
            if (!lkpMatch) {
                String[] lkpTypes = new String[]{};
                for (Schema.sObjectType lkpType : fieldDesc.getReferenceTo()) {
                    lkpTypes.add('' + lkpType);
                }
                throw err('Id value of type ' + idVal.getSObjectType() + ' is incompatible with Lookup field ' + 
                    path.strict + ' of type: ' + String.join(lkpTypes, ', '));
            }
            putVal = idVal;
        } else if (soapType == Schema.SOAPType.BOOLEAN) {
            if (oVal instanceof Boolean) {
                putVal = oVal == true;
            }
        } else if (soapType == Schema.SOAPType.DOUBLE || soapType == Schema.SOAPType.INTEGER) {
            if (oVal instanceof Decimal) {
                putVal = (Decimal) oVal;
            } else if (oVal instanceof String) {
                try {
                    putVal = Double.valueOf((String) oVal);
                } catch (Exception ignore) { }
            }
        } else if (soapType == Schema.SOAPType.DATE) {
            if (oVal instanceof Date) {
                putVal = (Date) oVal;
            } else if (oVal instanceof DateTime) {
                putVal = ((DateTime) oVal).date();
            } else if (oVal instanceof String) {
                try {
                    putVal = Date.valueOf((String) oVal);
                } catch (Exception ignore) { }
            }
        } else if (soapType == Schema.SOAPType.DATETIME) {
            if (oVal instanceof DateTime) {
                putVal = (DateTime) oVal;
            } else if (oVal instanceof Date) {
                putVal = DateTime.newInstance((Date) oVal, DateTime.newInstance(0, 0, 0, 0, 0, 0).time());
            } else if (oVal instanceof String) {
                try {
                    putVal = DateTime.valueOf((String) oVal);
                } catch (Exception ignore) { }
            }
        } else {
            throw err('Put-value on field ' + path.strict + ' of type ' + displayType.name() + ' is not currently supported');
        }

        if (putVal != null) {
            sobj.put(putName, putVal);
        } else {
            throw err('Value is incompatible with ' + displayType.name() + ' field ' + path.strict + ': ' + oVal);
        }
    }

    private static EntityDesc realPartToEntity(ObjectDesc holderObjDesc, RealDesc realPart) {
        String api;
        if (realPart.parentRelApi != null) {
            api = realPart.parentRelApi;
        } else if (realPart.childRel != null) {
            api = realPart.childRel.getRelationshipName();
        } else {
            api = '' + realPart.field;
        }
        EntityDesc entity = holderObjDesc.apiToEntity.get(api);
        if (entity != null) {
            return entity;
        } else {
            return new EntityDesc(holderObjDesc, realPart);
        }
    }

    private static RealDesc resolveRealPart(Schema.sObjectType objType, String realPart) {
        RealDesc resolved = new RealDesc();
        resolved.field = RKSecurity.resolveField(objType, realPart);
        if (resolved.field == null) {
            if (realPart.endsWithIgnoreCase('__r')) {
                resolved.field = RKSecurity.resolveField(objType, realPart.replaceFirst('(?i)__r$', '__c'));
                if (resolved.field != null) {
                    Schema.DescribeFieldResult fieldDesc = resolved.field.getDescribe();
                    if (fieldDesc.getType() == Schema.DisplayType.REFERENCE) {
                        resolved.parentRelApi = fieldDesc.getName().replaceFirst('(?i)__c$', '__r');
                    // else parent relationship is invalid for non-reference field type:
                    } else {
                        resolved.unresolved = true;
                        resolved.invalidParentRelType = fieldDesc.getType();
                    }
                }
            // else try to resolve as a standard parent lookup relationship:
            } else if (!realPart.endsWithIgnoreCase('__c') && !realPart.endsWithIgnoreCase('Id')) {
                resolved.field = RKSecurity.resolveField(objType, realPart + 'Id');
                if (resolved.field != null) {
                    resolved.parentRelApi = resolved.field.getDescribe().getName().replaceFirst('(?i)Id$', '');
                }
            }

            // last chance - try to resolve as a child relationship:
            if (resolved.field == null) {
                for (Schema.ChildRelationship childRel : objType.getDescribe().getChildRelationships()) {
                    if (childRel.getRelationshipName() == realPart) {
                        resolved.childRel = childRel;
                        break;
                    }
                }
                if (resolved.childRel == null) {
                    resolved.unresolved = true;
                }
            }
        }

        if (resolved.field != null) {
            resolved.fieldDesc = resolved.field.getDescribe();
        } else if (resolved.childRel == null) {
            resolved.unresolved = true;
        }
        return resolved;
    }

    public class PathDesc {
        public ObjectDesc objDesc {get; private set;} // the root Object type for this path
        public String sourcePath {get; private set;} // source path; no guaranteed letter-case and may contain mixed aliases or not
        // TODO: make a strict and real version of the path:
        //public String real {get; private set;} // the proper-case, fully qualified, non-aliased real path

        // string path consisting entirely of fully-qualified api names, in proper-case:
        public String strict {get; private set;} // the proper-case, fully qualified, non-aliased real path
        
        // string path consisting of api names, in proper-case, but with the masking namespace stripped where applicable:
        public String real {get{
            if (this.real != null) {
                return real;
            }
            String stripPrefix = objDesc.schemaDesc.maskingPrefix; //RKSecurity.getPackageNamespace();
            String[] v = new String[]{};
            Integer len = this.parts.size();
            for (Integer i=0; i < len; i++) {
                String api = parts[i].api;
                if (stripPrefix != null && api.startsWith(stripPrefix)) {
                    String strippedApi = api.substring(stripPrefix.length(), api.length());
                    if (strippedApi != 'c' && strippedApi != 'r') {
                        v.add(strippedApi);
                        continue;
                    }
                }
                v.add(api);
            }
            return this.real = String.join(v, '.');
        } private set;}
        
        // string path with bound aliases replacing api names where applicable, and with the masking namespace stripped where applicable:
        public String key {get{
            if (this.key != null) {
                return key;
            }
            String stripPrefix = objDesc.schemaDesc.maskingPrefix; //RKSecurity.getPackageNamespace();
            String[] v = new String[]{};
            Integer len = this.parts.size();
            for (Integer i=0; i < len; i++) {
                if (parts[i].alias != null) {
                    v.add(parts[i].alias);
                } else {
                    String api = parts[i].api;
                    if (stripPrefix != null && api.startsWith(stripPrefix)) {
                        String strippedApi = api.substring(stripPrefix.length(), api.length());
                        if (strippedApi != 'c' && strippedApi != 'r') {
                            v.add(strippedApi);
                            continue;
                        }
                    }
                    v.add(api);
                }
            }
            return this.key = String.join(v, '.');
        } private set;}

        //public RKSecurity.PathPart head {get; private set;}
        public EntityDesc head {get; private set;}
        public EntityDesc entity {get; private set;}
        // starts with this.head and ends with this.entity:
        public EntityDesc[] parts {get; private set;}

        private PathDesc(ObjectDesc objDesc) {
            this.objDesc = objDesc;
        }

        public override String toString() {
            return strict;
        }

        /*
        // TODO: deprecate 'aliased' property in favor of 'portablePath'
        // the stringification of this path with all possible entities replaced by their bound alias, and with the masking 
        // namespace (if any) removed:
        public String aliased {get{
            if (this.aliased != null) {
                return aliased;
            }
            String stripPrefix = objDesc.schemaDesc.maskingPrefix; //RKSecurity.getPackageNamespace();
            String[] v = new String[]{};
            Integer len = this.parts.size();
            for (Integer i=0; i < len; i++) {
                if (parts[i].alias != null) {
                    v.add(parts[i].alias);
                } else {
                    String api = parts[i].api;
                    if (stripPrefix != null && api.startsWithIgnoreCase(stripPrefix)) {
                        v.add(api.substring(stripPrefix.length(), api.length()));
                    } else {
                        v.add(api);
                    }
                }
            }
            return this.aliased = String.join(v, '.');
        } private set;}
        */

        public Boolean isCompound {get{
            return parts.size() > 1;
        }}

        public Boolean assertReadable {get{
            if (this.isReadable == true) {
                return true;
            } else {
                return calcReadable(true);
            }
        }}

        public Boolean isReadable {get{
            //return head.safeAccessPath != null;
            if (this.isReadable != null) {
                return this.isReadable;
            }
            return this.isReadable = calcReadable(false);
        } private set;}

        private Boolean calcReadable(Boolean asserts) {
            //return head.safeAccessPath != null;
            if (!entity.objDesc.objType.getDescribe().isAccessible()) {
                if (asserts == true) {
                    RKSecurity.logSecurityMiss(entity.objDesc.objType, RKSecurity.ACCESS_READ);
                }
                return false;
            }
            if (entity.isField || entity.isParentRel) {
                if (!entity.fieldDesc.isAccessible()) {
                    if (asserts == true) {
                        RKSecurity.logSecurityMiss(entity.objDesc.objType, entity.field, RKSecurity.ACCESS_READ);
                    }
                    return false;
                }
                if (entity.isParentRel) {
                    for (Schema.sObjectType parentType : entity.fieldDesc.getReferenceTo()) {
                        if (!parentType.getDescribe().isAccessible()) {
                            if (asserts == true) {
                                RKSecurity.logSecurityMiss(parentType, RKSecurity.ACCESS_READ);
                            }
                            return false;
                        }
                    }
                }
            } else if (entity.isChildRel) {
                Schema.sObjectType childType = entity.childRel.getChildSObject();
                if (!entity.childRel.getChildSObject().getDescribe().isAccessible()) {
                    if (asserts == true) {
                        RKSecurity.logSecurityMiss(entity.childRel.getChildSObject(), RKSecurity.ACCESS_READ);
                    }
                    return false;
                }
                if (!entity.childRel.getField().getDescribe().isAccessible()) {
                    if (asserts == true) {
                        RKSecurity.logSecurityMiss(entity.childRel.getChildSObject(), entity.childRel.getField(), RKSecurity.ACCESS_READ);
                    }
                    return false;
                }
            }
            return true;
        }
    }

    public class RealDesc {
        public Boolean unresolved = false;
        public String parentRelApi;
        public Schema.DisplayType invalidParentRelType;
        public Schema.sObjectField field;
        public Schema.DescribeFieldResult fieldDesc;
        public Schema.ChildRelationship childRel;

        public String api {get{
            if (parentRelApi != null) {
                return parentRelApi;
            } else if (childRel != null) {
                return childrel.getRelationshipName();
            } else if (field != null) {
                return '' + field;
            }
            return null;
        }}
    }

    private static Exception err(String msg) {
        AuraHandledException ae = new AuraHandledException(msg);
        ae.setMessage(msg);
        return ae;
    }

    private static Id parseId(String sid) {
        return Id.valueOf(sid);
    }

    public class Record {
        private Boolean safeReadMode = false;
        public ObjectDesc objDesc {get; private set;}
        public sObject obj;

        public Id Id {get{
            return obj != null ? obj.Id : null;
        }}

        private Record(SchemaDesc v, sObject obj) {
            this.objDesc = v.obj(obj.getSObjectType());
            this.obj = obj;
        }

        private Record(ObjectDesc objDesc, sObject obj) {
            this.objDesc = objDesc;
            this.obj = obj;
        }

        public Record copyFields(Record srcRecord, String delimitedAliasedFields) {
            // assert compatible sObject types:
            if (objDesc.objType != srcRecord.objDesc.objType) {
                throw err('Cannot copy fields from Object of type ' + srcRecord.objDesc.objType + ' to type ' + objDesc.objType);
            }
            for (String[] pathParts : splitPathsToParts(delimitedAliasedFields)) {
                if (pathParts.size() > 1) {
                    throw err('Cannot copy field value for compound path: ' + String.join(pathParts, '.'));
                }
                // need to get strict path from potentially aliased field:
                String aliasedField = pathParts[0];
                String strictField = objDesc.path(aliasedField).strict;
                obj.put(strictField, srcRecord.obj.get(strictField));
            }
            return this;
        }

        // !! The following type-specific value getters are written to be runtime flexible, and will auto-convert types as much as 
        // possible - this includes up-casts (truncation), down-casts, string parses, and first-of-collection operations. If you're 
        // coding to get the value of an entity, you'd better know WHAT that entity is, and whether it makes sense to convert to the 
        // target type according to the following rules. No hand-holding here if you get an unexpected value:

        // returns the String value of String fields
        // returns the toString value of non-String fields
        // throws error for all other entity types
        public String string(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            if (!entity.isField) {
                throw err('Cannot get a String value from ' + entity.describe());
            }
            return pathVal[1] != null ? String.valueOf(pathVal[1]) : null;
        }

        public Blob blob(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            Schema.SOAPType soapType = entity.fieldDesc.getSOAPType();
            if (!entity.isField) {
                throw err('Cannot get a Blob value from ' + entity.describe());
            } else if (soapType != Schema.SOAPType.BASE64BINARY) {
                throw err('Cannot get a Blob value from ' + entity.describe());
            }
            return pathVal[1] != null ? (Blob) pathVal[1] : null;
        }

        // returns the Decimal value of number fields
        // returns the parseFloat value of String fields, or errors if parse failed
        // returns the Array size of child relationships
        // throws error for all other entity types
        public Decimal number(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            Schema.SOAPType soapType = entity.fieldDesc.getSOAPType();
            if (entity.isChildRel) {
                return pathVal[1] != null ? ((sObject[]) pathVal[1]).size() : 0;
            } else if (!entity.isField) {
                throw err('Cannot get a Number value from ' + entity.describe());
            } else if (soapType != Schema.SOAPType.DOUBLE && soapType != Schema.SOAPType.INTEGER) {
                if (soapType == Schema.SOAPType.String) {
                    if (pathVal[1] == null) {
                        return null;
                    }
                    try {
                        return Decimal.valueOf((String) pathVal[1]);
                    } catch (Exception fallthrough) { }
                }
                throw err('Cannot get a Number value from ' + entity.fieldDesc.getType().name() + ' ' + entity.describe());
            }
            return (Decimal) pathVal[1];
        }

        // returns the Id value of Reference and Id fields
        // returns the record Id value of a Parent Relationship
        // returns the 1st record's Id value of a Child Relationship
        // returns the parseId of a String field, or throws error if parse fails
        // throws error for all other entity types
        public Id id(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;

            // JLB - Bugfix - Check for null before attempting to retrieve the field type. Otherwise this is
            // unusable for paths that aren't real fields.
            Schema.DisplayType type = entity.fieldDesc != null ? entity.fieldDesc.getType() : null;
            if (!entity.isField) {
                if (entity.isParentRel) {
                    sObject rec = (sObject) pathVal[1];
                    return rec != null ? rec.Id : null;
                } else if (entity.isChildRel) {
                    sObject[] recs = (sObject[]) pathVal[1];
                    return recs != null ? recs[0].Id : null;
                }
                throw err('Cannot get an Id value from ' + entity.describe());
            } else if (type != Schema.DisplayType.REFERENCE && type != Schema.DisplayType.ID) {
                if (entity.fieldDesc.getSOAPType() == Schema.SOAPType.STRING) {
                    if (pathVal[1] == null) {
                        return null;
                    }
                    try {
                        return parseId((String) pathVal[1]);
                    } catch (Exception fallthrough) { }
                }
                throw err('Cannot get an Id value from ' + type.name() + ' ' + entity.describe());
            }
            return (Id) pathVal[1];
        }

        // roughly like the ECMAScript "truthy" evaluation:
        public Boolean truthy(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            Schema.SOAPType soapType = entity.fieldDesc.getSOAPType();
            Object oVal = pathVal[1];
            if (!entity.isField) {
                throw err('Cannot get a Boolean value from ' + entity.describe());
            } else if (soapType == Schema.SOAPType.BOOLEAN) {
                return oVal == true;
            } else if (soapType == Schema.SOAPType.DOUBLE || soapType == Schema.SOAPType.INTEGER) {
                return oVal != null && (Decimal) oVal != 0;
            } else if (entity.fieldDesc.getType() == DisplayType.STRING) {
                return String.isNotBlank((String) oVal);
            } else {
                return oVal != null;
            }
        }

        // returns the Date value of Date fields
        // returns the Date component of DateTime fields
        // throws error for all other entity types
        public Date date(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            Schema.SOAPType soapType = entity.fieldDesc.getSOAPType();
            if (!entity.isField) {
                throw err('Cannot get a Date value from ' + entity.describe());
            } else if (soapType == Schema.SOAPType.DATETIME) {
                return pathVal[1] != null ? ((DateTime) pathVal[1]).date() : null;
            } else if (soapType != Schema.SOAPType.DATE) {
                throw err('Cannot get Date value from ' + soapType.name() + ' ' + entity.describe());
            }
            return (Date) pathVal[1];
        }

        // returns the Record of a Parent Relationship
        // returns the 1st Record of a Child Relationship
        // throws error for all other entity types
        public Record record(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            if (!entity.isParentRel) {
                if (entity.isChildRel) {
                    sObject[] recs = (sObject[]) pathVal[1];
                    return recs != null ? new Record(objDesc.schemaDesc, recs[0]) : null;
                }
                throw err('Cannot get a Record object from ' + entity.describe());
            }
            return new Record(objDesc.schemaDesc, (sObject) pathVal[1]);
        }

        // returns the Record Array of a Child Relationship
        // throws error for all other entity types
        public Record[] records(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            if (!entity.isChildRel) {
                throw err('Cannot get a Records array from ' + entity.describe());
            }
            sObject[] objs = (sObject[]) pathVal[1];
            Record[] recs = new Record[]{};
            if (objs != null) {
                for (sObject obj : objs) {
                    recs.add(new Record(objDesc.schemaDesc, obj));
                }
            }
            return recs;
        }

        // returns the sObject record of a Parent Relationship
        // returns the 1st sObject record of a Child Relationship
        // throws error for all other entity types
        public sObject sobject(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            if (!entity.isParentRel) {
                if (entity.isChildRel) {
                    sObject[] recs = (sObject[]) pathVal[1];
                    return recs != null ? recs[0] : null;
                }
                throw err('Cannot get a Record object from ' + entity.describe());
            }
            return (sObject) pathVal[1];
        }

        // returns the sObject Array of a Child Relationship
        // throws error for all other entity types
        public sObject[] sobjects(String entityPath) {
            Object[] pathVal = resolvePathAndVal(this, entityPath);
            EntityDesc entity = ((PathDesc) pathVal[0]).entity;
            if (!entity.isChildRel) {
                throw err('Cannot get a Records array from ' + entity.describe());
            }
            return (sObject[]) pathVal[1];
        }

        public Object val(String entityPath) {
            return resolvePathAndVal(this, entityPath)[1];
        }

        // TODO: deprecated in favor of toKeyMap()...
        public Map<String, Object> toSafeMap() {
            return RKSecurity.filterSObject(objDesc.schemaDesc, obj);
        }

        // TODO: rewrite RKSecurity logic into here...
        // TODO: only apply "Read" FLS if this.safeReadMode == true...
        public Map<String, Object> toKeyMap() {
            return RKSecurity.filterSObject(objDesc.schemaDesc, obj);
        }

        public Record put(String simplePath, Object oVal) {
            PathDesc path = objDesc.path(simplePath);
            if (!path.entity.isField) {
                throw err('Expected a field to set Record value, got: ' + path.entity.describe());
            } else if (path.isCompound) {
                throw err('Cannot use compound path to set Record value: ' + path.strict);
            }
            Vobj.put(objDesc, obj, path, oVal);
            return this;
        }
    }

    private static Object[] resolvePathAndVal(Record rec, String entityPath) {
        PathDesc pathDesc = rec.objDesc.path(entityPath);
        if (rec.safeReadMode == true && !pathDesc.assertReadable) {
            return new Object[]{ pathDesc, null };
        }
        sObject holder = rec.obj;
        Integer len = pathDesc.parts.size();
        Object val;
        for (Integer i=0; i < len; i++) {
            if (holder == null) {
                break;
            }
            EntityDesc entity = pathDesc.parts[i];
            if (i == len - 1) {
                if (entity.isField) {
                    val = holder.get(entity.api);
                } else if (entity.isParentRel) {
                    val = holder.getSObject(entity.api);
                } else if (entity.isChildRel) {
                    val = holder.getSObjects(entity.api);
                } else {
                    // TODO: should not be reachable?
                    val = entity.api;
                }
                break;
            } else {
                holder = holder.getSObject(entity.api);
            }
        }
        return new Object[]{ pathDesc, val };
    }

    public static String[] splitPaths(String delimitedPaths) {
        String[] paths = new String[]{};
        String[] chars = delimitedPaths != null ? delimitedPaths.split('') : new String[]{};
        Integer curs = -1;
        Integer len = delimitedPaths.length();

        // 0 => seek black token start or dot-continuation
        // 1 => consume word chars until 
        // 2 => black token ended; seek either dot-continuation, next black token start, or EOF
        Integer mode = 0;
        Integer tokStartIndex = -1;
        Integer pathContIndex = -1;
        Boolean pathContBroken = false;
        do {
            curs++;
            String ch = curs >= len ? '<EOF>' : chars[curs];
            // boundary mode; seek next black token:
            if (mode == 0) {
                if (ch.isAlphaNumeric() || ch == '_' || ch == '-') {
                    tokStartIndex = curs;
                    mode = 1;
                } else if (ch == '.') {
                    pathContIndex = paths.size() - 1;
                // else if it's a non-space separator char, this indicates a break of any possible path-continuation:
                } else if (!ch.isWhitespace()) {
                    pathContBroken = true;
                }
            } else if (mode == 1) {
                if (!(ch.isAlphaNumeric() || ch == '_' || ch == '-')) {
                    // terminate the current black token:
                    String tok = delimitedPaths.substring(tokStartIndex, curs);
                    if (pathContIndex > -1 && !pathContBroken) {
                        paths[pathContIndex] += '.' + tok;
                    } else {
                        paths.add(tok);
                    }
                    pathContIndex = -1;
                    pathContBroken = false;
                    mode = 0;
                    // backtrack because we don't want to consume the black-token terminating char:
                    curs--;
                }
            }

            if (ch == '<EOF>') {
                break;
            }
        } while (true);

        return paths;
    }

    public static List<String[]> splitPathsToParts(String delimitedPaths) {
        List<String[]> paths = new List<String[]>();
        String[] chars = delimitedPaths != null ? delimitedPaths.split('') : new String[]{};
        Integer curs = -1;
        Integer len = delimitedPaths != null ? delimitedPaths.length() : 0;

        // 0 => seek black token start or dot-continuation
        // 1 => consume word chars until 
        // 2 => black token ended; seek either dot-continuation, next black token start, or EOF
        Integer mode = 0;
        Integer tokStartIndex = -1;
        Integer pathContIndex = -1;
        Boolean pathContBroken = false;
        do {
            curs++;
            String ch = curs >= len ? '<EOF>' : chars[curs];
            // boundary mode; seek next black token:
            if (mode == 0) {
                if (ch.isAlphaNumeric() || ch == '_' || ch == '-') {
                    tokStartIndex = curs;
                    mode = 1;
                } else if (ch == '.') {
                    pathContIndex = paths.size() - 1;
                // else if it's a non-space separator char, this indicates a break of any possible path-continuation:
                } else if (!ch.isWhitespace()) {
                    pathContBroken = true;
                }
            } else if (mode == 1) {
                if (!(ch.isAlphaNumeric() || ch == '_' || ch == '-')) {
                    // terminate the current black token:
                    String tok = delimitedPaths.substring(tokStartIndex, curs);
                    if (pathContIndex > -1 && !pathContBroken) {
                        paths[pathContIndex].add(tok);
                    } else {
                        paths.add(new String[]{ tok });
                    }
                    pathContIndex = -1;
                    pathContBroken = false;
                    mode = 0;
                    // backtrack because we don't want to consume the black-token terminating char:
                    curs--;
                }
            }

            if (ch == '<EOF>') {
                break;
            }
        } while (true);

        return paths;
    }

    // Overridable interface for throwing path-parsing errors:
    public virtual class PathParseErrorHandler {
        public String rawPath;
        public Boolean isObjRootedPath;
        public String[] rawParts;
        public PartInfo part;
        //public Integer partCount;
        public String rawRoot; // only populated for object-rooted paths
        public ObjectDesc rootObjDesc;

        @TestVisible
        private void reset(String rawPath, Boolean isObjRootedPath, ObjectDesc rootObjDesc) {
            this.rawPath = rawPath;
            this.isObjRootedPath = isObjRootedPath == true;
            List<String[]> paths = splitPathsToParts(rawPath);
            this.rawParts = paths.size() > 0 ? paths[0] : new String[]{};
            this.rootObjDesc = rootObjDesc;
            this.rawRoot = rawParts.size() > 0 && isObjRootedPath == true ? rawParts[0] : null;
            this.part = null;
        }

        @TestVisible
        private PartInfo initPart(Integer index, ObjectDesc holderObjDesc) {
            this.part = new PartInfo();
            part.index = index;
            part.raw = rawParts[index];
            part.objDesc = holderObjDesc;
            return part;
        }
        
        public virtual Exception err(String msg) {
            AuraHandledException ae = new AuraHandledException(msg);
            ae.setMessage(msg);
            return ae;
        }

        public virtual void emptyPath() {
            throw err('Path cannot be empty');
        }

        public virtual void rootObj() {
            throw err('No Object Type is defined under alias or api identifier: ' + rawRoot);
        }

        public virtual void emptyPathAfterRootObj() {
            throw err('Expected path after root ' + rootObjDesc.describe());
        }

        public virtual void interiorPart() {
            if (part.properAlias != null) {
                throw err('Alias ' + part.raw + ' in path ' + rawPath + ' is not a Parent Relationship (' + part.entity.describe() + ')');
            } else {
                RealDesc resolved = part.real;
                if (resolved.unresolved) {
                    if (resolved.invalidParentRelType != null) {
                        throw err('Real part ' + part.raw + ' in path ' + rawPath + ' has the wrong underlying Field type [' + resolved.fieldDesc.getType().name() + '] for a Parent Relationship');
                    }
                    throw err('Real part ' + part.raw + ' in path ' + rawPath + ' is not a valid Field, Child Relationship, or Parent Relationship');
                } else if (resolved.parentRelApi == null) {
                    throw err('Real part ' + part.raw + ' in path ' + rawPath + ' was expected to be a Parent Relationship; got ' + (resolved.childRel != null ? 'Child Relationship' : 'Field'));
                }
            }
        }

        public virtual void terminatingPart() {
            // note that any matched alias (this.properAlias != null) ensures a valid terminating entity:
            RealDesc termReal = part.real;
            if (termReal != null && termReal.unresolved) {
                String prefix = rawParts.size() == 1 ? 'Real path ' + part.raw : 'Real part ' + part.raw + ' terminating path ' + rawPath;
                if (termReal.invalidParentRelType != null) {
                    throw err(prefix + ' has the wrong underlying Field type [' + termReal.fieldDesc.getType().name() + '] for a Parent Relationship');
                }
                throw err(prefix + ' is not a valid Field, Child Relationship, or Parent Relationship');
            }
        }
    }

    public class PartInfo {
        public Integer index;
        public String raw;
        public ObjectDesc objDesc;
        public String properAlias;
        public EntityDesc entity;
        public RealDesc real;
    }
}