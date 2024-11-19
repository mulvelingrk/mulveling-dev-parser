/*
 * Represents a set of functions hosted on the same class definition, sharing the same identifier name, and having a common static return 
 * type (with exception made for up to 1 dynamic return type function), but each with distinct formal arguments signatures -- i.e. function 
 * overloading.
 */
global class FunctionGroup {
    public DataDesc hostClass;
    // If this group holds a function with a compile-time dynamic return type (e.g. CASE), then it's recorded here.
    // Only 1 such dyna func can be defined per group, it can NEVER be overridden in subclasses, and it takes binding 
    // priority over any other dispatch-compatible functions in this group:
    public FunctionDesc dynaFunc; // if populated, dynaFunc.invokable must be an instanceof DynamicReturnType
    // all elements in funcs must define a non-null returnType (i.e. static return types):
    public FunctionDesc[] funcs = new FunctionDesc[]{};

    public FunctionGroup(DataDesc hostClass) {
        this.hostClass = hostClass;
    }

    // NOTE: Overloaded methods with more generic signatures should be defined BEFORE those with more specific 
    // signatures (e.g. define foo(Object x) before foo(String x)); this is because functions added later will 
    // be given higher binding priority (only applies to functions with static return type):
    public FunctionGroup add(FunctionDesc newFunc) {
        if (newFunc.isDynaFunc) {
            // can't have more than 1 dynamic function per group:
            System.assert(dynaFunc == null, 'Cannot define more that 1 variable return type function per overload group (' + newFunc.identifier + ')');
            this.dynaFunc = newFunc;
        } else {
            if (funcs.size() > 0) {
                FunctionDesc penFunc = funcs[funcs.size() - 1];
                if (newFunc.returnType !== penFunc.returnType) {
                    throw new DataDescException(newFunc.returnType.typeName + ' return type for function overload on ' + hostClass.typeName + 
                        '.' + newFunc.identifier + ' clashes with prior definition\'s return type of ' + penFunc.returnType.typeName);
                }
            }
            funcs.add(newFunc);
        }
        return this;
    }

    // Given another function (presumably currently outside this group), finds the highest binding priority function 
    // in this group that has the exact same formal argument signature. This method is used to determine function 
    // definition overrides in subclasses. Returns an index value encoded as follows:
    //     null => no match; override is invalid
    //     -1 => matches the dynaFunc; dynaFunc overrides are always invalid
    //     0...N => matches same index in this.funcs; override is valid
    public Integer findMatchingSignature(FunctionDesc thatFunc) {
        if (this.dynaFunc != null && this.dynaFunc.argSignatureMatches(thatFunc)) {
            return -1;
        } else {
            for (Integer i=0; i < this.funcs.size(); i++) {
                FunctionDesc thisFunc = this.funcs[i];
                if (thisFunc.argSignatureMatches(thatFunc)) {
                    return i;
                }
            }
        }
        return null;
    }
    
    // Given a list of physical argument types (compile-time determination), finds the highest binding-priority 
    // function with compatible arguments and returns it as a dispatchable object -- which contains the matching 
    // function's vtable index, plus instructions for valueOf conversions on imperfectly compatible argument slots.
    // this method is used by the compiler to resolve the function implementaiton for a given compile-time arguments array (types).
    // because of the way matching works, overloaded methods with more generic signatures should be defined BEFORE those with 
    // more specific signatures (e.g. define foo(Object x) before foo(String x))
    public Dispatchable getDispatchable(DataDesc[] argc) {
        Dispatchable disp;
        if (dynaFunc != null && (disp = dynaFunc.getDispatchable(argc)) != null) {
            return disp;
        } else {
            for (Integer i=this.funcs.size() - 1; i >= 0; i--) {
                FunctionDesc thisFunc = this.funcs[i];
                if ((disp = thisFunc.getDispatchable(argc)) != null) {
                    return disp;
                }
            }
        }
        return null;
    }
}