public class avSchemaUtils {

    /* SNIP - existing util code goes here... */

    public class NamespaceResolver {
        System.Callable thruCallable;

        // !! local-namespace subclasses should override this method
        public sObject[] query(String soql) {
            if (thruCallable != null) {
                return (sObject[]) thruCallable.call('query', new Map<String, Object>{ 'soql' => soql });
            } else {
                return Database.query(soql);
            }
        }

        // !! local-namespace subclasses should override this method
        public List<sObject[]> search(String sosl) {
            if (thruCallable != null) {
                return (List<sObject[]>) thruCallable.call('search', new Map<String, Object>{ 'sosl' => sosl });
            } else {
                return search.query(sosl);
            }
        }
        
        // !! local-namespace subclasses should override this method
        public Map<String, Schema.sObjectType> getGlobalDescribe() {
            if (thruCallable != null) {
                return (Map<String, Schema.sObjectType>) thruCallable.call('getGlobalDescribe', new Map<String, Object>{});
            } else {
                return Schema.getGlobalDescribe();
            }
        }
        
        // !! local-namespace subclasses should override this method. note that this method is safe for reference chains that resolve to a null holder
        // before the last field reference (i.e. returns null instead of de-referencing null):
        public Object getValue(sObject holder, String dotDelimitedRefChain) {
            if (thruCallable != null) {
                return thruCallable.call('getValue', new Map<String, Object>{ 'holder' => holder, 'dotDelimitedRefChain' => dotDelimitedRefChain });
            } else {
                sObject base = holder;
                String[] names = dotDelimitedRefChain.split('\\.');
                for (Integer i=0; i < names.size() - 1 && base != null; i++) {
                    base = base.getSObject(names[i]);
                }
                return base != null ? base.get(names[names.size() - 1]) : null;
            }
        }
        
        public void putValue(sObject holder, String fieldName, Object value) {
            if (thruCallable != null) {
                thruCallable.call('putValue', new Map<String, Object>{ 'holder' => holder, 'fieldName' => fieldName, 'value' => value });
            } else {
                holder.put(fieldName, value);
            }
        }
        
        public sObject queryOne(String soql) {
            if (thruCallable != null) {
                return (sObject) thruCallable.call('queryOne', new Map<String, Object>{ 'soql' => soql });
            } else {
                sObject[] results = this.query(soql);
                if (results.size() != 1) {
                    System.assert(false, 'Expected a single result row for query; got ' + results.size() + '. Original query: ' + soql);
                }
                return results[0];
            }
        }

        // MDU: The jInputField and jInputSelect components do not exist in argrc and are not needed:
        
        //public void addJInputField(Component.Apex.OutputPanel panel, sObject obj, String fieldPath, Boolean required, String jLabel) {
        //    panel.childComponents.add(new Component.jInputField(object=obj, field=fieldPath, required=required, jLabel=jLabel, inline=true));
        //}
        
        //public void addJInputSelect(Component.Apex.OutputPanel panel, SelectOption[] options, sObject obj, String fieldPath, Boolean required, String jLabel) {
        //    panel.childComponents.add(new Component.jInputSelect(options=options, object=obj, field=fieldPath, required=required, jLabel=jLabel, inline=true));
        //}
        
    }

    // Static variables and logic moved into outer avSchemaUtils class:

    public static NamespaceResolver pkgNamespace = new NamespaceResolver();
    public static NamespaceResolver[] namespaceStack = new NamespaceResolver[]{ pkgNamespace };
    public final static NamespaceResolver DefaultInstance = pkgNamespace;
    
    public static NamespaceResolver getActiveNamespace() {
        // return the top of stack:
        return namespaceStack[namespaceStack.size() - 1];
    }
    
    public static NamespaceResolver pushPkgNamespace() {
        return pushLocalNamespace(null);
    }
    
    public static NamespaceResolver pushLocalNamespace(NamespaceResolver localNamespace) {
        if (localNamespace == null) {
            localNamespace = pkgNamespace;
        }
        namespaceStack.add(localNamespace);
        return localNamespace;
    }
    
    // relinquishes the current namespace, if any. returns the old NamespaceResolver that is now relinquished:
    public static NamespaceResolver popNamespace() {
        NamespaceResolver relinquished;
        // always leave the 1st pkgNamespace on the stack:
        if (namespaceStack.size() > 1) {
            relinquished = namespaceStack.remove(namespaceStack.size() - 1);
        }
        
        return relinquished;
    }
    
    // initialized to an instance of "LocalNamespaceResolver" if that class is defined on the local org, otherwise falls back to a singleton
    // instance of the default impl (the default impl always binds to pkg-namespaced entities when available):
    public static NamespaceResolver PreferLocal;
    static {
        // Default resolver gives preference to pkg entities & fields over local of the same api name
        PreferLocal = pkgNamespace;
        // Look for a local Apex class named "LocalNamespaceResolver":
        Type localType = Type.forName('LocalNamespaceResolver');
        if (localType != null) {
            Object rizzo = localType.newInstance();
            //if (rizzo instanceof NamespaceResolver) {
            //    PreferLocal = (NamespaceResolver) rizzo;
            //} else 
            if (rizzo instanceof System.Callable) {
                //PreferLocal = new ThruCallableResolver((System.Callable) rizzo);
                PreferLocal = new NamespaceResolver();
                PreferLocal.thruCallable = (System.Callable) rizzo;
            }
        }
    }
}