/*
 * Mike Ulveling
 */
global class StringObject extends PrimitiveObject {
    
    global StringObject(Context ctx, String value) {
        super(ctx, 'String', value);
        this.customGetOwnProp = true;
        if (ctx.StringProto != null) {
            this.proto = ctx.StringProto;
        } else {
            // initialize the prototype instance:
            clobberOwnProperties(ctx, new Map<String, Object>{
                'toString' => new ToString(ctx),
                'valueOf' => new ValueOf(ctx),
                'charAt' => new CharAt(ctx),
                'charCodeAt' => new CharCodeAt(ctx),
                'concat' => new Concat(ctx),
                'indexOf' => new IndexOf(ctx),
                'lastIndexOf' => new LastIndexOf(ctx)
            }, PropertyDescrip.DataConfigWritePrivs);
        }
        
        defineOwnDataProperty(ctx, 'length', (Double) value.length(), PropertyDescrip.DataNoPrivs, false);
    }
    
    global override PropertyDescrip getOwnProperty(Context ctx, String p) {
        PropertyDescrip curr = props.get(p);
        if (curr == null) {
            Double index = Utils.toInteger(ctx, p);
            // return undefined if the index is negative or a decimal:
            if (!p.equals(Parser2.toString(Math.abs(index))))
                return null;
            
            String str = (String) this.primitiveValue;
            if (index >= str.length())
                return null;
            
            PropertyDescrip des = PropertyDescrip.DataNoPrivs.clone();
            des.enumerable = true;
            // !! this is a native limitation; in Apex we have no way to index a char past (2^31 - 1):
            if (index > Utils.Pow2_31_1)
                Utils.RangeError(ctx, 'The underyling host system cannot access string positions beyond ' + Utils.Pow2_31_1);
                
            des.value = str.mid(index.intValue(), 1);
            return des;
        } else 
            return curr;
    }
    
    // !! StringObject.enumerateOwn must also be overridden because we overrode getOwnProperty:
    global override void enumerateOwn(String[] enumList, Map<String, PlainObject> nameToOwner) {
        Integer[] intNames;
        Map<Integer, String[]> txtNames;
        for (String p: props.keySet()) {
            // note that this property may mask subsequent instances (of the same name) further up the proto chain, even if it's not enumerable:
            PlainObject maskingObj = nameToOwner.put(p, this);
            if (maskingObj != null) {
                // this property of the current object has been masked by an owner object further down the proto chain; put back the masking object:
                nameToOwner.put(p, maskingObj);
                continue;
            }
            
            PropertyDescrip des = props.get(p);
            if (des.enumerable) {
                Integer pint;
                if (p.isNumeric()) {
                    try {
                        pint = Integer.valueOf(p);
                        if (String.valueOf(pint) != p)
                            pint = null;
                    } catch (System.TypeException ignore) { }
                }
                
                if (pint != null) {
                    if (intNames == null)
                        intNames = new Integer[]{ pint };
                    else 
                        intNames.add(pint);
                } else {
                    if (txtNames == null) {
                        txtNames = new Map<Integer, String[]>{ des.localOrdinal => new String[]{ p } };
                    } else {
                        // get the list of all non-int names sharing the local ordinal as this property:
                        String[] siblings = txtNames.get(des.localOrdinal);
                        if (siblings == null)
                            txtNames.put(des.localOrdinal, new String[]{ p });
                        else
                            siblings.add(p);
                    }
                }
            }
        }
        
        // here's the only new logic for this override -- we must process the dynamic indexed-char properties:
        String strValue = (String) primitiveValue;
        for (Integer i=0; i < strValue.length(); i++) {
            String sindex = String.valueOf(i);
            PlainObject maskingObj = nameToOwner.put(sindex, this);
            if (maskingObj != null)
                // this property of the current object has been masked by an owner object further down the proto chain; put back the masking object:
                nameToOwner.put(sindex, maskingObj);
            else
                // note that the dynamic indexed-char properties (which this index must be if it's not been overridden/masked) are always enumerable:
                intNames.add(i);
        }
        
        if (intNames != null) {
            intNames.sort();
            for (Integer i: intNames)
                enumList.add(String.valueOf(i));
        }
        
        if (txtNames != null) {
            Integer[] ordinals = new List<Integer>(txtNames.keySet());
            ordinals.sort();
            for (Integer ord: ordinals)
                enumList.addAll(txtNames.get(ord));
        }
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'String', 1, ctx.StringProto);
        }
        
        global virtual override Object call(Context ctx, Object thisArg, Object[] argv) {
            return argv.size() > 0 ? Utils.toString(ctx, argv[0]) : '';
        }
        
        global Object construct(Context ctx, Object[] argv) {
            return new StringObject(ctx, argv.size() > 0 ? Utils.toString(ctx, argv[0]) : '');
        }
    }
    
    global virtual class ProtoBuiltin extends Function {
        String name;
        
        global ProtoBuiltin(Context ctx, String name, Integer length) {
            super(ctx, name, length);
            this.name = name;
        }
        
        Object illegalApply(Context ctx, Object thisArg) {
            return Utils.typeError(ctx, 'String.prototype.' + name + ' may not be applied to [' 
                    + Utils.valueTypeToString(ctx, thisArg) + ']');
        }
        
        Object intRangeError(Context ctx) {
            return Utils.rangeError(ctx, 'The underyling host system cannot access string positions beyond ' + Utils.Pow2_31_1);
        }
    }
    
    global class ToString extends ProtoBuiltin {
        global ToString(Context ctx) {
            super(ctx, 'toString', 0);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg instanceof StringObject)
                return ((StringObject) thisArg).primitiveValue;
            else if (thisArg instanceof String)
                return thisArg;
            else 
                return illegalApply(ctx, thisArg);
        }
    }
    
    global class ValueOf extends ProtoBuiltin {
        global ValueOf(Context ctx) {
            super(ctx, 'valueOf', 0);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg instanceof StringObject)
                return ((StringObject) thisArg).primitiveValue;
            else if (thisArg instanceof String)
                return thisArg;
            else
                return illegalApply(ctx, thisArg);
        }
    }
    
    global class CharAt extends ProtoBuiltin {
        global CharAt(Context ctx) {
            super(ctx, 'charAt', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg == null || thisArg == Utils.NUL)
                illegalApply(ctx, thisArg);
            
            String s = thisArg instanceof String ? (String) thisArg : Utils.toString(ctx, thisArg);
            Object objVal = argv.size() > 0 ? argv[0] : null;
            Integer intVal;
            Double position = 
                (objVal != null && objVal instanceof Double && (intVal = ((Double) objVal).intValue()) == objVal) 
                    ? intVal 
                    : (objVal == null ? 0 : Utils.toInteger(ctx, objVal));
            if (position < 0 || position >= s.length())
                return '';
            if (position > Utils.Pow2_31_1)
                intRangeError(ctx);
            
            return s.mid(position.intValue(), 1);
        }
    }
    
    // !! inexplicably, Apex doesn't provide a charCode method, so we use our own array to at least provide mappings for ASCII chars; we throw a
    // RangeError for non-ASCII chars:
    global class CharCodeAt extends ProtoBuiltin {
        global CharCodeAt(Context ctx) {
            super(ctx, 'charCodeAt', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg == null || thisArg == Utils.NUL)
                illegalApply(ctx, thisArg);
            
            String s = thisArg instanceof String ? (String) thisArg : Utils.toString(ctx, thisArg);
            Object objVal = argv.size() > 0 ? argv[0] : null;
            Integer intVal;
            Double position = 
                (objVal != null && objVal instanceof Double && (intVal = ((Double) objVal).intValue()) == objVal) 
                    ? intVal 
                    : (objVal == null ? 0 : Utils.toInteger(ctx, objVal));
            if (position < 0 || position >= s.length())
                return Utils.NaN;
            if (position > Utils.Pow2_31_1)
                intRangeError(ctx);
            
            Integer charCode = Utils.ASCII_CHARS.indexOf(s.mid(position.intValue(), 1));
            if (charCode < 0)
                Utils.rangeError(ctx, 'The underyling host system does not facilitate retrieval of character codes beyond the ASCII range');
            
            return (Double) charCode;
        }
    }
    
    global class Concat extends ProtoBuiltin {
        global Concat(Context ctx) {
            super(ctx, 'concat', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg == null || thisArg == Utils.NUL)
                illegalApply(ctx, thisArg);
            
            String s = thisArg instanceof String ? (String) thisArg : Utils.toString(ctx, thisArg);
            for (Object next: argv) {
                s += next instanceof String ? (String) next : Utils.toString(ctx, next);
            }
            return s;
        }
    }
    
    global class IndexOf extends ProtoBuiltin {
        global IndexOf(Context ctx) {
            super(ctx, 'indexOf', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg == null || thisArg == Utils.NUL)
                illegalApply(ctx, thisArg);
            
            String s = thisArg instanceof String ? (String) thisArg : Utils.toString(ctx, thisArg);
            if (s.length() > Utils.Pow2_31_1)
                intRangeError(ctx);
            
            Integer argLen = argv.size();
            String searchStr = Utils.toString(ctx, argLen > 0 ? argv[0] : null);
            Double pos = argLen < 2 || argv[1] == null ? 0 : Utils.toInteger(ctx, argv[1]);
            return (Double) s.indexOf(searchStr, Math.min(Math.max(pos, 0), s.length()).intValue());
        }
    }
    
    global class LastIndexOf extends ProtoBuiltin {
        global LastIndexOf(Context ctx) {
            super(ctx, 'lastIndexOf', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            if (thisArg == null || thisArg == Utils.NUL)
                illegalApply(ctx, thisArg);
            
            String s = Utils.toString(ctx, thisArg);
            if (s.length() > Utils.Pow2_31_1)
                intRangeError(ctx);
            
            Integer argLen = argv.size();
            String searchStr = Utils.toString(ctx, argLen > 0 ? argv[0] : null);
            
            Double numPos = argLen < 2 || argv[1] == null ? Utils.NaN : Utils.toNumber(ctx, argv[1]);
            Double pos = numPos == Utils.NaN ? Utils.Infinity : Utils.toInteger(ctx, numPos);
            return (Double) s.lastIndexOf(searchStr, Math.min(Math.max(pos, 0), s.length()).intValue());
        }
    }
}