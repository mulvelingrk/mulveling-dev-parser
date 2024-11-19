/*
FunctionDesc is used to define all aspects of a specific function:
    * An identifier name (e.g. "toString", "IF", "CASE", etc)
    * Formal arguments signature. Each formal argument slot specifies a data type (DataDesc) and optionally quanitifer
      bounds (quantifiers are only allowed in the final argument slot). Quantifiers are used to absorb a variable number
      of physical arguments (of the same type) in one formal arg slot.
    * Return type (DataDesc). Together, the formal arguments and return type comprise the function's signature. Return
      type can be left undeclared only if the function's method implementation implements the DynamicReturnType interface;
      this interface contains an additional method that will be called by the compiler to determine the return type via 
      cutom logic (e.g. "IF" has a return type determined by the types of its 2nd and 3rd physical arguments)
    * Method implementation. This is what executes the logic of the function, given a "this" binding and physical 
      argument values.
*/
global class FunctionDesc {
	// protects against formal arg changes after once existing bindings / dispatches may depend on this function's arg 
    // signature:
    public Boolean sealed = false;
    public DataDesc host;
    // class where this function signature was originally defined (note: if host !== inheritedHost then this represents an
    // override):
    public DataDesc inheritedHost;
    // index in vtable; must be same for all subclasses:
    public Integer vindex;
    // method name:
    public String identifier;

    // the combination of returnType and formalArgs defines this function's signature:

    // if returnType is initialized to null, then the Method subclass for "invokable" must implement DynamicReturnType 
    // (i.e. null implies a compile-time dynamic return type for the method):
    public DataDesc returnType;
    public Boolean isDynaFunc {get{ return invokable instanceof DynamicReturnType; }} //return returnType == null; }}
    // Formal argument signature:
    //   * Only the LAST arg slot may have a quantifier
    //   * Overloading occurs when multiple functions in a class share the same name identifier, but each has a distinct
    //     formal args signature; if 2 functions' arg signatures match, then it may represent an override, but not an overload
    //   * Functions that are overloaded form a FunctionGroup; within each group all functions must strictly match on return type 
    //   * Any function with a dynamic return type cannot be overridden, and it ALWAYS takes highest binding priority amongst all 
    //     dispatch-compatible overloads in the same function group
    FormalArg[] formalArgs;

    // A Method instance will declare its return type either statically via its "returnType" member, or dynamically by
    // implementing the DynamicReturnType interface:
    Method invokable;

    // use this constructor for functions with a dynamic (at compile-time) return type (special cases, like IF, CASE):
    global FunctionDesc(String identifier, DynamicReturnType invokable) {
        System.assert(false, 'TODO: implement');
        /*
        if (!IdentifierNamePatt.test(identifier)) {
            throw new DataDescException('Function name [' + identifier + '] is invalid');
        }
        this.identifier = identifier;
        this.formalArgs = new FormalArg[]{};
        this.invokable = invokable;
        */
    }

    // use this constructor for functions with a statically declared return type (99% of all functions):
    global FunctionDesc(DataDesc returnType, String identifier, Method invokable) {
        System.assert(false, 'TODO: implement');
        /*
        if (returnType == null) {
            throw new DataDescException('Function must specify a return type');
        }
        if (!IdentifierNamePatt.test(identifier)) {
            throw new DataDescException('Function name [' + identifier + '] is invalid');
        }
        this.returnType = returnType;
        this.identifier = identifier;
        this.formalArgs = new FormalArg[]{};
        this.invokable = invokable;
        */
    }

    // non-quantified "fixed" argument slot
    global FunctionDesc arg(DataDesc typeDesc) {
        return arg(typeDesc, null, null);
    }

    // "?" quantified arg slot:
    global FunctionDesc optionalArg(DataDesc typeDesc) {
        return arg(typeDesc, 0, 1);
    }

    // "*" quantified arg:
    global FunctionDesc starArg(DataDesc typeDesc) {
        return arg(typeDesc, 0, null);
    }

    // "+" quantified arg:
    global FunctionDesc plusArg(DataDesc typeDesc) {
        return arg(typeDesc, 1, null);
    }

    // if quantLower and/or quantUpper is non-null, then this is a quantified-argument:
    global FunctionDesc arg(DataDesc typeDesc, Integer quantLower, Integer quantUpper) {
        System.assert(!sealed, 'Cannot add argument to function "' + identifier + '" that has been sealed');
        FormalArg newArg = new FormalArg();
        newArg.typeDesc = typeDesc;
        newArg.quantLower = quantLower;
        newArg.quantUpper = quantUpper;
        Boolean newQuant = quantLower != null || quantUpper != null;
        if (formalArgs.size() > 0) {
            FormalArg penArg = formalArgs[formalArgs.size() - 1];
            if (penArg.quantLower != null || penArg.quantUpper != null) {
                if (newQuant) {
                    throw new DataDescException('Function cannot declare multiple quantified-argument slots');
                } else {
                    throw new DataDescException('Function cannot declare new arguments after a quantified-argument; it must occupy the last slot');
                }
        	}
        }
        return this;
    }

    // detemines whether another methods's formal argument slots *exactly* match this method's formal args
    global Boolean argSignatureMatches(FunctionDesc that) {
        if (!sealed) {
            sealed = true;
        }
        if (!that.sealed) {
            that.sealed = true;
        }
        if (this.formalArgs.size() != that.formalArgs.size()) {
            return false;
        }
        for (Integer i=0; i < this.formalArgs.size(); i++) {
            FormalArg slot = this.formalArgs[i];
            if (!this.formalArgs[i].equals(that.formalArgs[i])) {
                return false;
            }
        }
        return true;
    }

    // This version of getDispatchable is used for dynamic method invocations on an object instance (by client code):
    global Dispatchable getDispatchable(Value[] argv) {
        if (!sealed) {
            sealed = true;
        }
        DataDesc[] argc = new DataDesc[argv.size()];
        for (Integer i=0; i < argv.size(); i++) {
        	// TODO: handling of AbsoluteNull values?
            argc[i] = argv[i].typeDesc;
        }
        return getDispatchable(argc);
    }

    // This version of getDispatchable is used by the compiler generating object-code. If the given compile-time physical
    // argument types ("argc" array) are compatible with this function's formal arg slots (imperfect compatibility is allowed, 
    // quantifier arg slots are accounted for, etc), then a non-null Dispatchable is returned. A null return indicates to the 
    // compiler that this function's argument signature is not compatible with these physical args:
    global Dispatchable getDispatchable(DataDesc[] argc) {
    	System.assert(false, 'TODO: implement');
    	return null;
    	/*
        if (!sealed) {
            sealed = true;
        }
        Integer slotLen = formalArgs.size();
        Integer physicalLen = argc.size();
        // if any valueOf conversions are required in order to to assign the physical arg type to its formal arg slot type,
        // then the destination type is recorded here (i.e. imperfect assignment compatibility) -- arguments with perfect
        // assignment compatibility will record nulls in this array, and any physical arg with with no compatibility will 
        // cause this method to immediately return null (i.e. this function is not dispatchable for the given physical args):
        DataDesc[] argvConversions = new DataDesc[physicalLen];
        // if we have 0 formal arg slots, then 0 physical args indicates a match (fallthrough) with no argv conversion or slot 
        // alignment to perform; if we have 0 formal arg slots and 1 or more physical args, then no match (return null):
        if (slotLen == 0) {
            // if we have 0 formal arg slots a nonzero physical args, this signature cannot match:
            if (physicalLen > 0) {
                return null;
            }
            // else fallthrough...

        // else we have at least 1 formal arg slot and 0 or more physical args:
        } else {
            // "fixed" slots are slots without a quantifier (only the last slot can have a quantifier):
            FormalArg lastSlot = formalArgs[slotLen - 1];
            FormalArg quantifiedSlot;
            // tracks the current number of physical args that have been absorbed by the quantified slot:
            Integer quantifierMatches;
            Integer fixedSlotLen = slotLen;
            if (lastSlot.quantLower != null || lastSlot.quantUpper != null) {
                quantifiedSlot = lastSlot;
                quantifierMatches = 0;
                fixedSlotLen--;
            }
            // if we don't have enough physical arguments to fill the fixed (non-quantified) formal argument slots, then 
            // this signature cannot match:
            if (physicalLen < fixedSlotLen) {
                return null;
            }
            for (Integer i=0; i < physicalLen; i++) {
                FormalArg slot;
                if (i < fixedSlotLen) {
                    slot = formalArgs[i];
                } else if (quantifiedSlot != null) {
                    slot = quantifiedSlot;
                    quantifierMatches++;
                    // if this physical arg exceeds the qualtified formal arg's upper counter bound, then this signature
                    // cannot match:
                    if (quantifiedSlot.quantUpper != null && quantifierMatches > quantifiedSlot.quantUpper) {
                        return null;
                    }
                // if we have more physical args than can be covered by the formal args, and don't have a quantified 
                // formal arg to absorb the "extras", then this signature cannot match:
                } else {
                    return null;
                }

                Integer compat = slot.typeDesc.assignmentCompatibility(argc[i]);
                // if this physical arg type is incompatible with its corresponding formal arg's type, then this function 
                // signature does not match: 
                if (compat < 0) {
                    return null;
                // if this physical arg type is imperfectly compatible with its corresponding formal arg's type, then we 
                // must record that a data type conversion will be necessary upon dispatch (slot.typeDesc.valueOf(argv)): 
                } else if (compat > 0) {
                    argvConversions[i] = slot.typeDesc;
                }
            }

            // if we had a quantified formal argument, and its lower bound was not satisfied by the physical args, then
            // this signature cannot match:
            if (quantifiedSlot != null && quantifiedSlot.quantLower != null && quantifierMatches < quantifiedSlot.quantLower) {
                return null;
            }
        }
        // if we reach here then the physical args are compatible with this function's formal arguments signature:

        */
    }
}