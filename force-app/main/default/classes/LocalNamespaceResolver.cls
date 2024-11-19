/*
 * Mike Ulveling
 * RKDEV-32683 - Callable variant of argrc.NamespaceResolver (dynamic dispatch) so that we don't have to modify the globally-facing API
 * of argrc package code, and can issue this Relationship Graph fix as a patch.
 */
global class LocalNamespaceResolver implements System.Callable {
    
    global Object call(String action, Map<String, Object> args) {
        if (action == 'query') {
            String soql = (String) args.get('soql');
            return Database.query(soql);
        } else if (action == 'queryOne') {
            String soql = (String) args.get('soql');
            sObject[] results = Database.query(soql);
            if (results.size() != 1) {
                System.assert(false, 'Expected a single result row for query; got ' + results.size() + '. Original query: ' + soql);
            }
            return results[0];
        } else if (action == 'search') {
            String sosl = (String) args.get('sosl');
            return Search.query(sosl);
        } else if (action == 'getGlobalDescribe') {
            return Schema.getGlobalDescribe();
        } else if (action == 'getValue') {
            sObject holder = (sObject) args.get('holder');
            String dotDelimitedRefChain = (String) args.get('dotDelimitedRefChain');
            sObject base = holder;
            String[] names = dotDelimitedRefChain.split('\\.');
            for (Integer i=0; i < names.size() - 1 && base != null; i++) {
                base = base.getSObject(names[i]);
            }
            return base != null ? base.get(names[names.size() - 1]) : null;
        } else if (action == 'putValue') {
            sObject holder = (sObject) args.get('holder');
            String fieldName = (String) args.get('fieldName');
            Object value = args.get('value');
            holder.put(fieldName, value);
        } else if (action == 'putValue') {
            sObject holder = (sObject) args.get('holder');
            String fieldName = (String) args.get('fieldName');
            Object value = args.get('value');
            holder.put(fieldName, value);
        // MDU - we don't need jInputField and jInputSelect components in argrc:
        /*} else if (action == 'addJInputField') {
            Component.Apex.OutputPanel panel = (Component.Apex.OutputPanel) args.get('panel');
            sObject obj = (sObject) args.get('obj');
            String fieldPath = (String) args.get('fieldPath'); 
            Boolean required = (Boolean) args.get('required');
            String jLabel = (String) args.get('jLabel');
            panel.childComponents.add(new Component.jInputField(object=obj, field=fieldPath, required=required, jLabel=jLabel, inline=true));
        } else if (action == 'addJInputSelect') {
            Component.Apex.OutputPanel panel = (Component.Apex.OutputPanel) args.get('panel');
            sObject obj = args.get('obj');
            SelectOption[] options = (SelectOption[]) args.get('options');
            String fieldPath = (String) args.get('fieldPath'); 
            Boolean required = (Boolean) args.get('required');
            String jLabel = (String) args.get('jLabel');
            panel.childComponents.add(new Component.jInputSelect(options=options, object=obj, field=fieldPath, required=required, jLabel=jLabel, inline=true));
        */
        } else {
            System.assert(false, 'Method [' + action + '] not supported!');
        }
        return null;
    }
    
    // RKDEV-15528 - MDU - Aug 20, 2020 - Changed from private to global for Salesforce Critical Update:
    // https://releasenotes.docs.salesforce.com/en-us/spring20/release-notes/rn_apex_publicConstructorsInMgdPackages.htm
    global LocalNamespaceResolver(){}
    
    // singleton:
    global static LocalNamespaceResolver instance = new LocalNamespaceResolver();
}