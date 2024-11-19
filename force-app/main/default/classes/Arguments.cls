/*
 * Mike Ulveling
 * 
 * ECMAScript5 10.6
 */
global class Arguments extends PlainObject {
    public PlainObject mapped;
    
    public Arguments(Context ctx, MFunction mfunc, Object[] argv, DeclarativeEnv env) {
        // pass our desired [[className]] to the PlainObject constructor:
        super(ctx, 'Arguments');
        this.customGetOwnProp = true;
        
        Integer nameCount = mfunc.code.formalParams.size();
        PropertyDescrip len = PropertyDescrip.DataConfigWritePrivs.clone();
        len.value = argv.size();
        this.defineOwnProperty(ctx, 'length', len, false);
        
        Boolean notStrict = !mfunc.code.strict;
        // !! note this local var masks this.mapped:
        PlainObject mapped;
        Set<String> mappedNames;
        for (Integer i=argv.size() - 1; i >= 0; i--) {
            PropertyDescrip indxDesc = PropertyDescrip.DataAllPrivs.clone();
            indxDesc.value = argv[i];
            this.defineOwnProperty(ctx, String.valueOf(i), indxDesc, false);
            if (notStrict && i < nameCount) {
                String name = mfunc.code.formalParams[i].lexeme;
                if (mappedNames == null || !mappedNames.contains(name)) {
                    if (mappedNames == null) {
                        mappedNames = new Set<String>{ name };
                        mapped = new PlainObject(ctx);
                    } else
                        mappedNames.add(name);
                    
                    PropertyDescrip mappedDesc = PropertyDescrip.AccessorNoPrivs.clone();
                    mappedDesc.configurable = true;
                    mappedDesc.getter = new MappedArgGetter(ctx, name, env);
                    mappedDesc.setter = new MappedArgSetter(ctx, name, env);
                    mapped.defineOwnProperty(ctx, String.valueOf(i), mappedDesc, false);
                }
            }
        }
        
        // if this.mapped is not null, then the [[Get]], [[GetOwnProperty]], [[DefineOwnProperty]], and [[Delete]] methods will execute alternate
        // behavior from this point forward (i.e. they'll additionally check this.mapped object for a matching property definition):
        this.mapped = mapped;
        if (notStrict) {
            PropertyDescrip calleeDesc = PropertyDescrip.DataConfigWritePrivs.clone();
            calleeDesc.value = mfunc;
            this.defineOwnProperty(ctx, 'callee', calleeDesc, false);
        } else {
            PropertyDescrip callerDesc = PropertyDescrip.AccessorNoPrivs.clone();
            callerDesc.getter = callerDesc.setter = ctx.ArgsThrowTypeError;
            this.defineOwnProperty(ctx, 'caller', callerDesc, false);
            PropertyDescrip calleeDesc = PropertyDescrip.AccessorNoPrivs.clone();
            calleeDesc.getter = calleeDesc.setter = ctx.ArgsThrowTypeError;
            this.defineOwnProperty(ctx, 'callee', calleeDesc, false);
        }
    }
    
    global override Object get(Context ctx, String name) {
        if (mapped == null)
            return super.get(ctx, name);
        
        PropertyDescrip isMapped = mapped.getOwnProperty(ctx, name);
        if (isMapped == null) {
            Object v = super.get(ctx, name);
            // TODO: strict should be a property on the base Function class...
            if (name == 'caller' && v instanceof MFunction && ((MFunction) v).code.strict)
                Utils.typeError(ctx, 'The \'caller\', \'callee\', and \'arguments\' properties may not be accessed on ' 
                        + 'strict mode functions or the arguments objects for calls to them');
            return v;
        } else
            return mapped.get(ctx, name);
    }
    
    global override PropertyDescrip getOwnProperty(Context ctx, String name) {
        PropertyDescrip des = super.getOwnProperty(ctx, name);
        if (mapped == null || des == null)
            return des;
        
        PropertyDescrip isMapped = mapped.getOwnProperty(ctx, name);
        if (isMapped != null)
            des.value = mapped.get(ctx, name);
        
        return des;
    }
    
    // TODO: define a custom [[Put] for slightly improved efficiency...
    
    global override Boolean defineOwnProperty(Context ctx, String name, PropertyDescrip des, Boolean throwError) {
        if (mapped == null)
            return super.defineOwnProperty(ctx, name, des, throwError);
        
        PropertyDescrip isMapped = mapped.getOwnProperty(ctx, name);
        Boolean allowed = super.defineOwnProperty(ctx, name, des, false);
        if (!allowed) {
            if (throwError)
                Utils.typeError(ctx, '\'' + name + '\' may not be defined on the Arguments object');
            else return false;
        }
        if (isMapped != null) {
            if (des.isAccessor == true)
                mapped.deleteProperty(ctx, name, false);
            else if (des.isAccessor == false) {
                if (des.value != null || des.hasValue == true)
                    mapped.put(ctx, name, des.value, throwError);
                if (des.writable == false)
                    mapped.deleteProperty(ctx, name, false);
            }
        }
        return true;
    }
    
    global override Boolean deleteProperty(Context ctx, String name, Boolean throwError) {
        if (mapped == null)
            return super.deleteProperty(ctx, name, throwError);
        
        PropertyDescrip isMapped = mapped.getOwnProperty(ctx, name);
        Boolean result = super.deleteProperty(ctx, name, throwError);
        if (result == true && isMapped != null)
            mapped.deleteProperty(ctx, name, false);
        
        return result;
    }
    
    global class MappedArgGetter extends Function {
        String name;
        DeclarativeEnv closureEnv;
        
        global MappedArgGetter(Context ctx, String name, DeclarativeEnv closureEnv) {
            super(ctx, 'ArgumentsMappedGet', 0);
            this.name = name;
            this.closureEnv = closureEnv;
        }
        
        // here we must exactly emulate the following ECMAScript code in native Apex code (assume the function's scope is this.env): 
        // function() { "use strict"; return <name>; }
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            // we know for a fact that this mapped arg binds to the <name> declaration of the closure's non-null DeclarativeEnv base, so we can
            // inline Utils.getValue's equivalent logic to improve efficiency:
            return closureEnv.bindingVals.get(name);
        }
    }
    
    global class MappedArgSetter extends Function {
        String name;
        DeclarativeEnv closureEnv;
        
        global MappedArgSetter(Context ctx, String name, DeclarativeEnv closureEnv) {
            super(ctx, 'ArgumentsMappedSet', 1);
            this.name = name;
            this.closureEnv = closureEnv;
        }
        
        // here we must exactly emulate the following ECMAScript code in native Apex code (assume the function's scope is this.env):
        // function(<name>_arg) { "use strict"; <name> = <param>; }
        global override Object call(Context ctx, Object thisBinding, Object[] argv) {
            // we know for a fact that this mapped arg binds to the <name> declaration of the closure's non-null DeclarativeEnv base, so we can
            // inline Utils.putValue's equivalent logic to improve efficiency:
            closureEnv.bindingVals.put(name, argv.size() == 0 ? null : argv[0]);
            return null;
        }
    }
}