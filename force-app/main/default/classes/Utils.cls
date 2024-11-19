/*
 * Mike Ulveling
 * 
 * ECMAScript runtime support methods, utilities, and type conversions
 */
global class Utils {
    
    // Discrete Native Dispatch
    // throws RuntimeException or synchronously returns the function's return value:
    global static Object nativeDispatchCall(Context ctx, Object funcVal, Object thisArg, Object[] argv) {
        return VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, funcVal, thisArg, argv);
    }
    
    // Discrete Native Dispatch
    // throws RuntimeException or synchronously returns the constructor's return value:
    global static Object nativeDispatchConstruct(Context ctx, Object funcVal, Object[] argv) {
        return VirtualMachine.dispatchConstruct(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, funcVal, argv);
    }
    
    global static Object getValue(Context ctx, Object val) {
        if (!(val instanceof Reference) || val == null)
            return val;
        
        Reference ref = (Reference) val;
        if (ref.base == null)
            return ReferenceError(ctx, '\'' + ref.name + '\' is not defined');
        else if (ref.base instanceof Environment)
            return ((Environment) ref.base).getBindingValue(ctx, ref.name, ref.strict);
        else if (ref.base instanceof PlainObject)
            return ((PlainObject) ref.base).get(ctx, ref.name);
        // note that References cannot be created with a base value of null or undefined...
        else {
            PrimitiveObject transObj;
            PropertyDescrip dataProp;
            if (ref.base instanceof String) {
                // we attempt to bypass the creation of a transient StringObject by first assuming that ref.name is probably either "length" or one
                // of the data properties on the standard built-in String prototype:
                if (ref.name.equals('length'))
                    return (Double) ((String) ref.base).length();
                else {
                    dataProp = ctx.StringProto.props.get(ref.name);
                    // string objects override [[getOwnProperty]] to account for indexed chars, so we should only bypass the transient object if we've
                    // found an "own" data property on String.prototype:
                    if (dataProp == null || dataProp.isAccessor == true)
                        transObj = new StringObject(ctx, (String) ref.base);
                }
                
            } else if (ref.base instanceof Double) {
                // we attempt to bypass the creation of a transient NumberObject by first assuming that we'll probably find a data property for
                // ref.name in the Number or Object prototypes:
                dataProp = ctx.NumberProto.props.get(ref.name);
                if (dataProp == null)
                    dataProp = ctx.ObjectProto.props.get(ref.name);
                if (transObj != null && dataProp.isAccessor == true)
                    transObj = new NumberObject(ctx, (Double) ref.base);
                
            } else if (ref.base instanceof Boolean) {
                // we attempt to bypass the creation of a transient BooleanObject by first assuming that we'll probably find a data property for
                // ref.name in the Boolean or Object prototypes:
                dataProp = ctx.BooleanProto.props.get(ref.name);
                if (dataProp == null)
                    dataProp = ctx.ObjectProto.props.get(ref.name);
                if (dataProp != null && dataProp.isAccessor == true)
                    transObj = new BooleanObject(ctx, (Boolean) ref.base);
            } else
                throw new InternalException('Illegal reference base type [' + valueTypeToString(ctx, ref.base) + '] for getValue');
            
            if (transObj == null)
                return dataProp == null ? null : dataProp.value;
            // else ref.name must point to an accessor property; in this case we'll have created a transient instance of PrimitiveObject in order to
            // perform a more rigorous [[get]] for ref.name:
            else 
                return transObj.get(ctx, ref.name);
        }
    }
    
    global static void putValue(Context ctx, Object v, Object w) {
        if (!(v instanceof Reference) || v == null)
            ReferenceError(ctx, 'Invalid left-hand side in assignment');
        
        Reference ref = (Reference) v;
        if (ref.base == null) {
            if (ref.strict)
                referenceError(ctx, '\'' + ref.name + '\' is not defined');
            else
                ctx.globalObj.put(ctx, ref.name, w, false);
        } else if (ref.base instanceof Environment)
            ((Environment) ref.base).setMutableBinding(ctx, ref.name, w, ref.strict);
        else if (ref.base instanceof PlainObject)
            ((PlainObject) ref.base).put(ctx, ref.name, w, ref.strict);
        // note that References cannot be created with a base value of null or undefined...
        else {
            // create a transient wrapper object for the primitive value base -- for now, we don't attempt to bypass instantiation of this transient
            // object, because of the nontrivial error checking specified for this scenario:
            PrimitiveObject transObj;
            if (ref.base instanceof String)
                transObj = new StringObject(ctx, (String) ref.base);
            else if (ref.base instanceof Double)
                transObj = new NumberObject(ctx, (Double) ref.base);
            else if (ref.base instanceof Boolean)
                transObj = new BooleanObject(ctx, (Boolean) ref.base);
            else
                throw new InternalException('Illegal reference base type [' + valueTypeToString(ctx, ref.base) + '] for putValue');
            
            // here we implement a custom [[Put]] for the transient object, as described in 8.7.2:
            String p = ref.name;
            if (!transObj.canPut(ctx, p)) {
                if (ref.strict)
                    typeError(ctx, 'Cannot set property \'' + p + '\' of [' + valueTypeToString(ctx, ref.base) + ']');
                else return;
            }
            PropertyDescrip ownDesc = transObj.getOwnProperty(ctx, p);
            if (ownDesc.isAccessor == false) {
                if (ref.strict)
                    typeError(ctx, 'Cannot set property \'' + p + '\' of primitive value [' + valueTypeToString(ctx, ref.base) + ']');
                else return;
            }
            PropertyDescrip des = transObj.getProperty(ctx, p);
            if (des.isAccessor == true) {
                VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, des.setter, transObj, new Object[]{ w });
            } else if (ref.strict)
                TypeError(ctx, 'Cannot set property \'' + p + '\' of primitive value [' + valueTypeToString(ctx, ref.base) + ']');
        }
    }
    
    global static String toString(Context ctx, Object val) {
        if (val == null)
            return 'undefined';
        else if (val instanceof String)
            return (String) val;
        else if (val instanceof Double)
            return Parser2.toString((Double) val);
        else if (val instanceof Boolean)
            return String.valueOf(val);
        else if (val == NullSingleton.NUL)    
            return 'null';
        // else, it must be an instance of PlainObject -- recursively invoke this method on the result of [[DefaultValue]], which must return a
        // primitive value:
        else return toString(ctx, ((PlainObject) val).defaultValue(ctx, STRING_HINT));
    }
    
    global static PlainObject toObject(Context ctx, Object val) {
        if (val == null)
            TypeError(ctx, 'Cannot convert undefined to an object');
        else if (val instanceof String)
            return new StringObject(ctx, (String) val);
        else if (val instanceof Double)
            return new NumberObject(ctx, (Double) val);
        else if (val instanceof Boolean)
            return new BooleanObject(ctx, (Boolean) val);
        else if (val == NullSingleton.NUL)
            TypeError(ctx, 'Cannot convert null to an object');
        
        return (PlainObject) val;
    }
    
    global static Object toPrimitive(Context ctx, Object val, Integer preferredType) {
        if (val instanceof PlainObject)
            return ((PlainObject) val).defaultValue(ctx, preferredType);
        else
            return val;
    }
    
    // truthy or falsey:
    global static Boolean toBoolean(Context ctx, Object val) {
        return val == true || (val != false && val != null && val != NUL && val != 0 && val != '' && val != MinusZero && val != NaN);
    }
    
    global static Double toNumber(Context ctx, Object val) {
        if (val == null)
            return NaN;
        else if (val == NUL)
            return 0;
        else if (val instanceof Double)
            return (Double) val;
        else if (val instanceof Boolean)
            return val == true ? 1 : 0;
        else if (val instanceof String) {
            String s = ((String) val).trim();
            if (s.length() == 0)
                return 0;
            else if (s.startsWithIgnoreCase('0x')) {
                if (s.length() == 2)
                    return NaN;
                    
                Double num = 0;
                for (Integer i=2; i < s.length(); i++) {
                    num *= 16;
                    Integer nextDigitVal = Lexer2.HexadecimalDigits.indexOfIgnoreCase(s.mid(i, 1));
                    if (nextDigitVal < 0)
                        return NaN;
                    
                    num += nextDigitVal;
                }
                return num;
            } else {
                Double num;
                try {
                    // TODO: once again, it's difficult to prove that Double.valueOf will exactly meet the ECMAScript spec in this context -- for now
                    // we'll stick with it because at worst it's VERY close to spec, and it's FAR easier and more efficient than rolling our own:
                    num = Double.valueOf(s);
                } catch (TypeException e) {
                    num = NaN;
                }
                return num;
            }
        // else, it must be a PlainObject:
        } else
            return toNumber(ctx, ((PlainObject) val).defaultValue(ctx, null));
    }
    
    global static Double toInteger(Context ctx, Object val) {
        Double num = toNumber(ctx, val);
        if (num == NaN)
            return 0;
        else if (num == 0 || num == MinusZero || num == Infinity || num == -Infinity)
            return num;
        else
            return (num > 0 ? 1 : -1) * Math.floor(Math.abs(num));
    }
    
    global static Double toInt32(Context ctx, Object val) {
        /*
        // shortcut for number values that can fit into an Apex Integer without loss of information:
        if (val instanceof Double) {
            Double dval = (Double) val;
            Integer ival = dval.intValue();
            if (ival == dval)
                return dval;
        }
        */
        
        Double num = toNumber(ctx, val);
        if (num == NaN || num == 0 || num == MinusZero || num == Infinity || num == -Infinity)
            return 0;
        
        Double posInt = (num > 0 ? 1 : -1) * Math.floor(Math.abs(num));
        Double int32bit;
        // here's how we implement the "modulo" function -- note that this is different from the % "remainder" function, and Apex's Math.mod is
        // useless to our needs:
        if (posInt > 0)
            int32bit = posInt - Math.floor(Math.abs(posInt / Pow2_32)) * Pow2_32;
        else
            int32bit = posInt + Math.ceil(Math.abs(posInt / Pow2_32)) * Pow2_32;
        
        if (int32bit >= Pow2_31)
            return int32bit - Pow2_32;
        else
            return int32bit;
    }
    
    global static Double toUint32(Context ctx, Object val) {
        Double num = toNumber(ctx, val);
        if (num == NaN || num == 0 || num == MinusZero || num == Infinity || num == -Infinity)
            return 0;
        
        Double posInt = (num > 0 ? 1 : -1) * Math.floor(Math.abs(num));
        // here's how we implement the "modulo" function -- note that this is different from the % "remainder" function, and Apex's Math.mod is
        // useless to our needs:
        if (posInt > 0)
            return posInt - Math.floor(Math.abs(posInt / Pow2_32)) * Pow2_32;
        else
            return posInt + Math.ceil(Math.abs(posInt / Pow2_32)) * Pow2_32;
    }
    
    global static Double toUint16(Context ctx, Object val) {
        Double num = toNumber(ctx, val);
        if (num == NaN || num == 0 || num == MinusZero || num == Infinity || num == -Infinity)
            return 0;
        
        Double posInt = (num > 0 ? 1 : -1) * Math.floor(Math.abs(num));
        // here's how we implement the "modulo" function -- note that this is different from the % "remainder" function, and Apex's Math.mod is
        // useless to our needs:
        if (posInt > 0)
            return posInt - Math.floor(Math.abs(posInt / Pow2_16)) * Pow2_16;
        else
            return posInt + Math.ceil(Math.abs(posInt / Pow2_16)) * Pow2_16;
    }
    
    /*
    // same as toInt32, except that this method performs a final lossless "type cast" of the result to an Apex Integer:
    global static Integer toNativeInt32(Context ctx, Object val) {
        // shortcut for number values that can fit into an Apex Integer without loss of information:
        if (val instanceof Double) {
            Double dval = (Double) val;
            Integer ival = dval.intValue();
            if (ival == dval)
                return ival;
        }
        
        Double num = toNumber(ctx, val);
        if (num == NaN || num == 0 || num == MinusZero || num == Infinity || num == -Infinity)
            return 0;
        
        Double posInt = (num > 0 ? 1 : -1) * Math.floor(Math.abs(num));
        Double int32bit;
        // here's how we implement the "modulo" function -- note that this is different from the % "remainder" function:
        if (posInt > 0)
            int32bit = posInt - Math.floor(Math.abs(posInt / Pow2_32)) * Pow2_32;
        else
            int32bit = posInt + Math.ceil(Math.abs(posInt / Pow2_32)) * Pow2_32;
        
        if (int32bit >= Pow2_31)
            return (int32bit - Pow2_32).intValue();
        else
            return int32bit.intValue();
    }
    */
    
    global static Boolean strictEquality(Context ctx, Object x, Object y) {
        // use the Apex '==' operator to do the bulk of the comparison work:
        if (x == y) {
            // handle special cases where an Apex '==' result of true maps to an ECMAScript '===' result of false:
            if (x == null)
                // if x is undefined and x == y in Apex, then y must be undefined, and undefined === undefined in ECMAScript:
                return true;
            // remember, Apex foolishly uses a case-insensitive comparison for its '==' operator when applied to two strings:
            else if (x instanceof String)
                return ((String) x).equals((String) y);
            else if (x instanceof Double)
                // NaN === NaN returns false in ECMAScript:
                return x != NaN && y != NaN;
            // ok, the operands must be '===':
            else
                return true;
        // an Apex '==' result of false maps to an ECMAScript '===' result of false in all cases except for that of the operands -0 and +0:
        } else if (x != null && y != null && x instanceof Double && y instanceof Double) {
            // -0 strictly equals +0 and vice-versa:
            return ((Double) x).intValue() == 0 && ((Double) y).intValue() == 0;
        } else 
            return false;
    }
    
    global static Boolean abstractEquality(Context ctx, Object x, Object y) {
        // use the Apex '==' operator to do the bulk of the comparison work:
        if (x == y) {
            // handle special cases where an Apex '==' result of true maps to an ECMAScript '==' result of false:
            if (x == null)
                return true;
            // remember, Apex foolishly uses a case-insensitive comparison for its '==' operator when applied to two strings:
            else if (x instanceof String)
                return ((String) x).equals((String) y);
            else if (x instanceof Double)
                return x != NaN && y != NaN;
            // ok, the operands must be '===':
            else
                return true;
        }
        
        // handle special cases where an Apex '==' result of false maps to an ECMAScript '==' result of true:
        if (x == null)
            return y == NUL;
        else if (y == null)
            return x == NUL;
        
        Boolean xbool, ybool;
        if ((xbool = x instanceof Boolean) != (ybool = y instanceof Boolean))
            if (xbool)
                return abstractEquality(ctx, xbool == true ? 1 : 0, y);
            else
                return abstractEquality(ctx, x, ybool == true ? 1 : 0);
        else if (xbool && ybool)
            return false;
        
        Boolean xnum = x instanceof Double, ystr = y instanceof String;
        if (xnum && ystr)
            return abstractEquality(ctx, x, toNumber(ctx, y));
        Boolean xstr = x instanceof String, ynum = y instanceof Double;
        if (xstr && ynum)
            return abstractEquality(ctx, toNumber(ctx, x), y);
        
        if ((xstr || xnum) && y instanceof PlainObject)
            return Utils.abstractEquality(ctx, x, toPrimitive(ctx, y, null));
        else if ((ystr || ynum) && x instanceof PlainObject)    
            return abstractEquality(ctx, toPrimitive(ctx, x, null), y);
        
        return false;
    }
    
    // abstract relational comparison 11.8.5
    global static Boolean abstractRelComp(Context ctx, Object x, Object y, Boolean leftFirst) {
        Object px, py;
        if (leftFirst) {
            px = toPrimitive(ctx, x, NUMBER_HINT);
            py = toPrimitive(ctx, y, NUMBER_HINT);
        } else {
            py = toPrimitive(ctx, y, NUMBER_HINT);
            px = toPrimitive(ctx, x, NUMBER_HINT);
        }
        
        if (px == null || py == null)
            return null;
        
        if (px instanceof String && py instanceof String) {
            return ((String) px).compareTo((String) py) < 0;
        } else {
            Double nx = Utils.toNumber(ctx, px), ny = Utils.toNumber(ctx, py);
            // Apex's Double-typed comparison via '<' actually matches the ECMAScript spec (including for "special" operands e.g. -0, Infinity,
            // NaN, etc):
            return Utils.toNumber(ctx, px) < Utils.toNumber(ctx, py);
        }
    }
    
    // !! all instances of PlainObject share this ordinal counter, to be used for sorting their enumerable property names:
    global static Integer OrdinalCounter = 0;
    
    global static Object Undefined = null;
    global static Object NUL = NullSingleton.NUL;
    global static final Object[] EMPTY_ARGV = new Object[]{};
    
    global static Double NaN = Double.valueOf('NaN');
    global static Double Infinity = Double.valueOf('Infinity');
    global static Double MinusInfinity = Double.valueOf('-Infinity');
    global static Double MinusZero = Double.valueOf('-0');
    global static Long Pow2_16 = Long.valueOf('1') << 16;
    global static Long Pow2_31 = Long.valueOf('1') << 31;
    global static Long Pow2_31_1 = Pow2_31 - 1; // the maximum positive integer value for a signed 32-bit Integer variable
    global static Long Pow2_32 = Long.valueOf('1') << 32;
    global static Long Pow2_32_1 = Pow2_32 - 1; // the maximum ECMAScript Array length
    
    global static final Integer NUMBER_HINT = 0;
    global static final Integer STRING_HINT = 1;
    
    // ugh, there's no "charCodeAt" method in Apex, so we'll at least provide this functionality for ASCII chars (via an indexOf(ascii_ch) on this
    // string):
    global static final String ASCII_CHARS = String.fromCharArray(new Integer[]{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,
            26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,
            71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,
            112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,
            146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,177,178,179,
            180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,
            214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,
            248,249,250,251,252,253,254,255});
    
    /*
    Remainder function, a.k.a. '%' operator:
    remainder(x, y) => x - sign(x) * sign(y) * floor(abs(x / y)) * y
     7 %  4 =  3
     7 % -4 =  3
    -7 %  4 = -3
    -7 % -4 = -3

    function remainder(x, y) {
        if (y == 0)
            return NaN;
        else if (x == 0)
            return 0;
        else
            return x - sign(x) * sign(y) * floor(abs(x / y)) * y;
    }
    
    The notation “x modulo y” (y must be finite and nonzero) computes a value k of the same sign as y (or zero) such that abs(k) < abs(y) and x−k = q × y for some integer q.
     7 modulo  4 =  3 (q =  1, k =  3)
     7 modulo -4 = -1 (q = -2, k = -1)
    -7 modulo  4 =  1 (q = -2, k =  1)
    -7 modulo -4 = -3 (q =  1, k = -3)
    
    function modulo(x, y) {
        if (y == 0 || x == 0 || sign(x) === sign(y))
            return remainder(x, y);
        else 
            return x + ceil(abs(x / y)) * y;
    }
    */
    
    // 9.12
    global static Boolean sameValue(Context ctx, Object x, Object y) {
        if (x != null && x instanceof String)
            return y instanceof String && ((String) x).equals((String) y);
        else
            return x == y;
    }
    
    global static Object referenceError(Context ctx, String msg) {
        throw new RuntimeException(ctx, new ReferenceError(ctx, msg));
    }
    
    global static Object typeError(Context ctx, String msg) {
        throw new RuntimeException(ctx, new TypeError(ctx, msg));
    }
    
    global static Object rangeError(Context ctx, String msg) {
        throw new RuntimeException(ctx, new RangeError(ctx, msg));
    }
    
    global static String valueTypeToString(Context ctx, Object val) {
        if (val == null)
            return 'undefined';
        else if (val instanceof String)
            return 'string';
        else if (val instanceof Double)
            return 'number';
        else if (val instanceof Boolean)
            return 'boolean';
        else if (val == NullSingleton.NUL)    
            return 'null';
        else if (val instanceof PlainObject)
            return ((PlainObject) val).className;
        else
            return '<unknown type>';
    }
    
    // clones obj and replaces the new objs' props map with a new map that contains a shallow clone of each original own prop:
    global PlainObject deepCloneOwnProps(PlainObject obj) {
        PlainObject newObj = obj.clone();
        Map<String, PropertyDescrip> newProps = new Map<String, PropertyDescrip>();
        for (String p: obj.props.keySet()) {
            newProps.put(p, obj.props.get(p).clone());
        }
        newObj.props = newProps;
        return newObj;
    }
}