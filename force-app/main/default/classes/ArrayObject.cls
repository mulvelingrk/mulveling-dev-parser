/*
 * Mike Ulveling
 * 
 * Bet you didn't realize ECMAScript arrays actually work like this...
 */
global class ArrayObject extends PlainObject {
    // internal length property for fast access and checks:
    Long length;
    
    global ArrayObject(Context ctx) {
        super(ctx, 'Array');
        if (ctx.ArrayProto != null)
            this.proto = ctx.ArrayProto;
        else
            // initialize the prototype instance:
            this.proto = ctx.ObjectProto;
        
        this.length = 0;
        PropertyDescrip lenDesc = PropertyDescrip.DataNoPrivs.clone();
        lenDesc.writable = true;
        lenDesc.value = (Double) this.length;
        // note there's no need to set localOrdinal because this property is not enumerable
        props.put('length', lenDesc);
        //defineOwnProperty(ctx, 'length', lenDesc, false);
    }

    // this constructor must NOT be used to instantiate the standard built-in Array prototype;
    // !! each element in initElements must be either an Elision or a valid ECMAScript value;
    // !! note that by directly putting a property for each element (rather than by going through [[Put]] or [[DefineOwnProperty]], we bypass
    // potential modifications to the standard built-in Array prototype that may have otherwise precluded the setting of these elements:
    global ArrayObject(Context ctx, Object[] initElements) {
        super(ctx, 'Array');
        if (ctx.ArrayProto != null)
            this.proto = ctx.ArrayProto;
        else
            throw new InternalException('Invalid constructor used for the standard built-in Array prototype');
        
        this.length = initElements.size();
        PropertyDescrip lenDesc = PropertyDescrip.DataNoPrivs.clone();
        lenDesc.writable = true;
        lenDesc.value = (Double) this.length;
        // note there's no need to set localOrdinal because this property is not enumerable
        props.put('length', lenDesc);
        
        for (Integer i=0; i < initElements.size(); i++) {
            Object elmt = initElements[i];
            // elisions create "holes" in the array
            if (elmt != Elision.Instance) {
                PropertyDescrip elmtDesc = PropertyDescrip.DataAllPrivs.clone();
                elmtDesc.value = elmt;
                elmtDesc.localOrdinal = Utils.OrdinalCounter++;
                props.put(String.valueOf(i), elmtDesc);
            }
        }
    }
    
    global override void put(Context ctx, String p, Object v, Boolean throwError) {
        PlainObject host = this;
        PropertyDescrip des;
        do {
            des = host.props.get(p);
            if (des != null)
                break;
            
            host = host.proto;
        } while (host != null);
        
        // if we didn't find an own prop nor an inherited one then submit the value to ArrayObject's special [[DefineOwnProperty]]:
        if (des == null) {
            // note that ArrayObject is always extensible, so we can discard that check...
            des = PropertyDescrip.DataAllPrivs.clone();
            des.value = v;
            // in contrast to PlainObject.[[Put]], which creates new property descriptor objects and maps them directly into props, here we go
            // through arrayDefineOwnProperty to allow special handling on array elements and length:
            ArrayObject.arrayDefineOwnProperty(ctx, this, p, des, throwError);
            
        // else if the existing prop is an accessor -- no difference between an own vs. inherited property in this case:
        } else if (des.isAccessor) {
            if (des.setter == null) {
                if (throwError)
                    Utils.TypeError(ctx, 'Cannot write to array accessor ' + p + ' without a setter');
                else return;
            }
            VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, des.setter, this, new Object[]{ v });
            
        // else we have an existing own or inherited data prop:
        } else {
            if (!des.writable) {
                if (throwError)
                    Utils.TypeError(ctx, 'Cannot write to array property ' + p + ' that is not writable');
                else return;
            }
            // note that ArrayObject is always extensible, so we can discard that check on inherited data props...
            // if we have an inherited data prop, or the prop name is "length", then create a new "own" data prop with all priviledges and the given
            // value, then pass it through to ArrayObject's special [[DefineOwnProperty]] method:
            if (host !== this) {
                des = PropertyDescrip.DataAllPrivs.clone();
                des.value = v;
                // in contrast to PlainObject.[[Put]], which creates new property descriptor objects and maps them directly into props, here we go
                // through arrayDefineOwnProperty to allow special handling on array elements and length:
                ArrayObject.arrayDefineOwnProperty(ctx, this, p, des, throwError);
            // if the property name is "length" (this is guaranteed to be a pre-existing "own" property on an ArrayObject), then pass the new value
            // through to ArrayObject's special [[DefineOwnProperty]] method:
            } else if ('length'.equals(p)) {
                des = new PropertyDescrip();
                des.value = v;
                des.hasValue = true;
                // in contrast to PlainObject.[[Put]], which creates new property descriptor objects and maps them directly into props, here we go
                // through arrayDefineOwnProperty to allow special handling on array elements and length:
                ArrayObject.arrayDefineOwnProperty(ctx, this, p, des, throwError);
                
            // else we have an existing and writable own data prop that is not "length", so we can simply set the value:
            } else {
                des.value = v;
            }
        }
    }
    
    global override Boolean defineOwnProperty(Context ctx, String p, PropertyDescrip des, Boolean throwError) {
        return arrayDefineOwnProperty(ctx, this, p, des, throwError);
    }
    
    static final String DecimalDigits = '0123456789';
    
    public static Boolean arrayDefineOwnProperty(Context ctx, ArrayObject arr, String p, PropertyDescrip des, Boolean throwError) {
        // the "own" properties on the ArrayObject:
        Map<String, PropertyDescrip> props = arr.props;
        PropertyDescrip lenDesc;
        // this will be set to non-null when p represents a valid element 15.4:
        Long index;
        // this will be set to non-null when we need to do a length update following standard processing:
        Long newLen;
        
        // element processing -- 
        // try to resolve p to an array index (a.k.a. element); p must be all ASCII decimal digits of 10 or fewer. for example, of the property names
        // "1.0", "01", and "1", only the "1" is an element:
        Integer plen;
        if ((plen = p.length()) < 11 && p.indexOfAnyBut(DecimalDigits) == -1 && plen > 0) {
            // if the property name is numeric and we can assure it's small enough to fit into an Integer (i.e. fewer than 10 digits), then we can
            // parse it very simply:
            if (plen < 10) {
                // property names, other than "0", containing 1 or more left-pad zeros are not elements (e.g. "01" is not an element):
                if (plen == 1 || !p.startsWith('0'))
                    // with the above checks, this Integer parse must succeed:
                    index = Integer.valueOf(p);
            // else it's a large int that may exceed the allowable array index range; apply more the rigorous check prescribed in the spec:
            } else {
                Long pUint32 = Utils.toUint32(ctx, Double.valueOf(p)).longValue();
                if (String.valueOf(pUint32) == p && pUint32 < Utils.Pow2_32_1)
                    index = pUint32;
            }
            
            // if this is a valid element whose index exceeds the current array length, then we must try to expand the array:
            if (index != null && index >= arr.length) {
                // "length" is guaranteed to be found as a data property in the props map since this is an ArrayObject:
                lenDesc = props.get('length');
                // we have to reject right now if we need to update a "length" property that's not writable:
                if (!lenDesc.writable) {
                    if (throwError)
                        Utils.TypeError(ctx, 'Cannot write to array index [' + index + '] that exceeds current Array length [' + 
                                arr.length + '], because the length is not writable');
                    else return false;
                }
                // setup a signal for a length update following the standard processing, then fallthrough to standard processing:
                newLen = index + 1;
            }
            // fallthrough to standard processing...
            
        // length processing; will fallthrough except in the case where the new length is contracting. note that in the case of a length contraction,
        // spanning non-configurable elements, we may both update the length property and Reject):
        } else if ('length'.equals(p)) {
            if (des.value != null || des.hasValue == true) {
                // note that for length, the string values "1.00", "1.0" (etc) and the number value 1 are all treated the same; this differs from
                // array index processing. if the new length's value is a Double (the most common case), then we can apply simpler range-check logic:
                if (des.value != null && des.value instanceof Double) {
                    Double dNewLen = (Double) des.value;
                    newLen = dNewLen.longValue();
                    if (dNewLen != Utils.MinusZero && (newLen != dNewLen || newLen < 0 || newLen > Utils.Pow2_32_1)) {
                        if (throwError)
                            Utils.RangeError(ctx, 'Invalid array length: ' + Utils.toString(ctx, dNewLen));
                        else return false;
                    }
                    
                // else, apply the more generic and rigorous (i.e. slower) range check as prescribed in the spec:
                } else {
                    newLen = Utils.toUint32(ctx, des.value).longValue();
                    if (newLen != Utils.toNumber(ctx, des.value))
                        if (throwError)
                            Utils.RangeError(ctx, 'Invalid array length: ' + Utils.toString(ctx, des.value));
                        else return false;
                }
                
                //des = des.clone();
                // update the passed-in Desc's value payload with the resolved numerical length:
                des.value = (Double) newLen;
                // if we're contracting this array's length, then we may need to delete elements:
                if (newLen < arr.length) {
                    // "length" is guaranteed to be found as a data property in the props map since this is an ArrayObject:
                    lenDesc = props.get('length');
                    if (!lenDesc.writable)
                        Utils.TypeError(ctx, 'Cannot set array length to [' + newLen + ']; length is not writable');
                    else return false;
                    
                    // TODO: note that the spec asks us to call the default [[DefineOwnProperty]] (with the local throwError as final argument, and
                    // writable set to true (deferring a Desc.writable==false)) at 15.4.5.1[3.j.] and proceed contingent upon success, but I don't
                    // see how this call could possibly fail given the preceding checks (i.e. we know the length property is currently a writable
                    // data property). therefore, I've skipped this call and will set the length property's value after the determination is made
                    // below (checking for any non-configurable contracted elements) whether we can actually reach that length value:
                    for (Long delIndex=arr.length - 1; delIndex >= newLen; delIndex--) {
                        String delName = String.valueOf(delIndex);
                        // as per spec, we're only interested in elements that are "own" properties on this array; ignore inherited props (an
                        // inherited prop is not an element). note how we use props.remove instead of props.get, because props.remove kindy returns
                        // us the removed delIndex prop (if any), and in the common case we won't need to put it back into props:
                        PropertyDescrip delDesc = props.remove(delName);
                        // [[Delete]] of this element will fail only it's an existing own property with configurable==false:
                        if (delDesc != null) {
                            if (!delDesc.configurable) {
                                // [[Delete]] failed; we can't contract the array length past this element's index + 1:
                                // 1. put the prop back into the props map
                                // 2. contract the length as much as we're able, also transferring a false writable flag if that's been requested:
                                // 3. Reject:
                                props.put(delName, delDesc);
                                arr.length = delIndex + 1;
                                lenDesc.value = (Double) arr.length;
                                if (des.writable == false)
                                    lenDesc.writable = false;
                                
                                if (throwError)
                                    Utils.TypeError(ctx, 'Cannot set array length less than ' + arr.length 
                                            + ', because the element at index [' + (arr.length - 1) + '] cannot be removed. Length was set to ' 
                                            + arr.length);
                                else return false;
                            } 
                            // else no-op; we've already removed delIndex from the props map...
                        }
                    }
                    
                    // if we made it here then we encountered no restrictions to our contraction:
                    arr.length = newLen;
                    lenDesc.value = (Double) newLen;
                    if (des.writable == false)
                        lenDesc.writable = false;
                    
                    // no fallthrough:
                    return true;
                }
                // else newLen >= oldLen; fallthrough to standard processing...
            }
            // else, the property is "length" but Desc doesn't carry a new value for it; fallthrough to standard processing...
        }
        
        // standard processing --
        // the following is basically a copy-and-paste from PlainObject[[DefineOwnProperty]], except that: 1. we can make a few minor optimizations
        // based on immutable properties of the ArrayObject (e.g. we know arr.customGetOwnProp==false and arr.extensible=true), and 2. we follow
        // the standard logic with a check for a new length value that's been verified & setup by the prior array index processing:
        
        PropertyDescrip curr = props.get(p);
        if (curr == null) {
            if (des.isAccessor == true)
               curr = PropertyDescrip.AccessorNoPrivs.clone();
            else
               curr = PropertyDescrip.DataNoPrivs.clone();
            
            curr.localOrdinal = Utils.OrdinalCounter++;
            props.put(p, curr);
            // fallthrough to overwrite curr with properties provided by des...
        } else {
            
            // !! note that the "return true" no-op checks described by the spec are redundant because the subsequent validation checks perform the
            // same guards (e.g. Utils.sameValue), so we skip them to save all those comparison ops...
            
            if (!curr.configurable) {
                if (des.configurable == true) {
                    if (throwError)
                        Utils.typeError(ctx, 'Cannot convert ' + p + ' to a configurable property');
                    else return false;
                }
                if (des.enumerable != null && des.enumerable != curr.enumerable) {
                    if (throwError)
                        Utils.typeError(ctx, 'Cannot convert ' + p + ' to an enumerable property');
                    else return false;
                }
            }
            
            // generic descriptors have completed all necessary validation; continue validation for data and accessor descriptors:
            if (des.isAccessor != null) {
                if (des.isAccessor != curr.isAccessor) {
                    if (!curr.configurable) {
                        if (throwError)
                            Utils.typeError(ctx, 'Cannot convert property ' + p + ' from ' 
                                    + (curr.isAccessor ? 'accessor' : 'data') + ' to ' 
                                    + (des.isAccessor ? 'accessor' : 'data'));
                        else return false;
                    }
                    PropertyDescrip oldCurr = curr;
                    // convert to accessor or data:
                    if (des.isAccessor)
                        curr = PropertyDescrip.AccessorNoPrivs.clone();
                    else
                        curr = PropertyDescrip.DataNoPrivs.clone();
                    
                    curr.configurable = true; // obviously, the property was/is configurable
                    curr.enumerable = oldCurr.enumerable;
                    curr.localOrdinal = Utils.OrdinalCounter++;
                    props.put(p, curr);
                    // fallthrough to overwrite curr with properties provided by des...
                
                // a configurable prop accepts all changes; if not configurable then we must do the following additional validation for the
                // incoming data or accessor prop; if configurable then simply fallthrough to overwrite curr with properties provided by des...
                } else if (!curr.configurable) {
                    if (curr.isAccessor == false) {
                        if (!curr.writable) {
                            if (des.writable == true) {
                                if (throwError)
                                    Utils.typeError(ctx, 'Cannot convert ' + p + ' to a writable property');
                                else return false;
                            } else if ((des.value != null || des.hasValue == true) && !Utils.sameValue(ctx, des.value, curr.value)) {
                                if (throwError)
                                    Utils.typeError(ctx, 'Cannot write into read-only property ' + p);
                                else return false;
                            }
                        }
                    } else {
                        if (des.getter != null && !Utils.sameValue(ctx, des.getter, curr.getter)) {
                            if (throwError)
                                Utils.typeError(ctx, 'Cannot change getter for non-configurable property ' + p);
                            else return false;
                        }
                        if (des.setter != null && !Utils.sameValue(ctx, des.setter, curr.setter)) {
                            if (throwError)
                                Utils.typeError(ctx, 'Cannot change setter for non-configurable property ' + p);
                            else return false;
                        }
                    }
                }
            }
        }
        
        if (des.configurable != null) curr.configurable = des.configurable;
        if (des.enumerable != null) curr.enumerable = des.enumerable;
        if (des.isAccessor == false) {
            if (des.writable != null) curr.writable = des.writable;
            // checking for hasValue==true allows us to change an existing data property to the value undefined:
            if (des.value != null || des.hasValue == true) {
                curr.value = des.value;
                // TODO: the following may be redundant because data descriptors in an object are presumed to be fully populated (i.e. assumed
                // to have a value):
                //curr.hasValue = true;
            }
        } else if (des.isAccessor == true) {
            if (des.getter != null) curr.getter = des.getter;
            if (des.setter != null) curr.setter = des.setter;
        }
        
        // post-processing to enact a new length that's been determined prior to standard processing, in the array index processing:
        if (newLen != null) {
            // if we reach here with a non-null newLen, then we must have previously set lenDesc (non-null) in the element processing:
            lenDesc.value = (Double) newLen;
            arr.length = newLen;
        }
        
        return true;
    }
    
    global class Constructor extends Function implements Constructible {
        public Constructor(Context ctx) {
            super(ctx, 'Array', 1, ctx.ArrayProto);
        }
        
        global virtual override Object call(Context ctx, Object thisArg, Object[] argv) {
            return this.construct(ctx, argv);
        }
        
        global Object construct(Context ctx, Object[] argv) {
            if (argv.size() == 1) {
                ArrayObject arr = new ArrayObject(ctx);
                Object lenArg = argv[0];
                Long uintLen;
                if (lenArg == null || !(lenArg instanceof Double)) {
                    uintLen = 1;
                    PropertyDescrip elmt0 = PropertyDescrip.DataAllPrivs.clone();
                    elmt0.value = lenArg;
                    elmt0.localOrdinal = Utils.OrdinalCounter++;
                    arr.props.put('0', elmt0);
                    //arr.defineOwnDataProperty(ctx, '0', lenArg, PropertyDescrip.DataAllPrivs, false);
                
                // else the length argument must have been passed in as a Double:
                } else {
                    uintLen = Utils.toUint32(ctx, (Double) lenArg).longValue();
                    // we have to give the Double value -0 a special pass, since in Apex, Double.valueOf('-0') != 0:
                    if (uintLen != lenArg && lenArg != Utils.MinusZero || uintLen > Utils.Pow2_31_1)
                        Utils.RangeError(ctx, 'Invalid array length: ' + Utils.toString(ctx, lenArg) + 
                                (uintLen == lenArg && uintLen > Utils.Pow2_31_1 ? '; length exceeds the host system\'s maximum value' : ''));
                }
                
                arr.length = uintLen;
                PropertyDescrip lenDesc = PropertyDescrip.DataNoPrivs.clone();
                lenDesc.writable = true;
                lenDesc.value = (Double) uintLen;
                // note there's no need to set localOrdinal because this property is not enumerable
                arr.props.put('length', lenDesc);
                return arr;
            } else {
                // we don't need to check for elisions
                // TODO: consider adding a constructor bool param to bypass the elision check in this case:
                return new ArrayObject(ctx, argv);
            }
        }
    }
    
    global class IsArray extends Function {
        public IsArray(Context ctx) {
            super(ctx, 'isArray', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Object arg = argv.size() == 0 ? null : argv[0];
            return arg != null && arg instanceof PlainObject && 'Array'.equals(((PlainObject) arg).className);
        }
    }
    
    global class ToString extends Function {
        public ToString(Context ctx) {
            super(ctx, 'toString', 0);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            PlainObject o = Utils.toObject(ctx, thisArg);
            Object func = o.get(ctx, 'join');
            Callable call;
            if (func != null && func instanceof Callable)
                call = (Callable) func;
            else
                call = ctx.ObjectToString;
                
            return VirtualMachine.dispatchCall(ctx, VirtualMachine.DISPATCH_SYNCHRONOUS, null, call, o, Utils.EMPTY_ARGV);
        }
    }
    
    // omg 'join' is also an Apex reserved word...
    global class JoinArray extends Function {
        public JoinArray(Context ctx) {
            super(ctx, 'join', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Object next;
            String[] parts = new String[0];
            Long len;
            
            Boolean isArray;
            PlainObject obj;
            if (thisArg != null && ((isArray = thisArg instanceof ArrayObject) || thisArg instanceof PlainObject)) {
                if (isArray) {
                    // this version optmized for actual arrays; it makes assumptions based on Array not overriding getOwnProperty and the high
                    // likelihood of element indexes being "own" properties on this object (i.e. we assume it's not very sparse):
                    ArrayObject arr = (ArrayObject) thisArg;
                    len = arr.length;
                    if (len.intValue() != len)
                        Utils.RangeError(ctx, 'Join length [' + len + '] exceeds the host system\'s maximum value');
                    else if (len == 0)
                        return '';
                    
                    // build a String[] of parts to join:
                    for (Integer k=0; k < len; k++) {
                        String sk = String.valueOf(k);
                        PropertyDescrip prop = arr.props.get(sk);
                        if (prop == null)
                            // inherited prop; use proto.[[Get]] to look for it:
                            next = arr.proto.get(ctx, sk);
                        else if (prop.isAccessor)
                            // accessor prop; use [[Get]] to resolve its value:
                            next = arr.get(ctx, sk);
                        else
                            // else we guessed right; it's an own data prop:
                            next = prop.value;
                        
                        parts.add(next == Utils.undefined || next == Utils.nul ? '' : Utils.toString(ctx, next));
                    }
                } else
                    obj = (PlainObject) thisArg;
                    // fallthrough to generic version...
            } else
                obj = Utils.toObject(ctx, thisArg);
            
            // if we've already done the optimised parts collection for an array object, then len will be not-null:
            if (len == null) {
                // generic "duck typing" way of collecting the string parts for non-array objects:
                len = Utils.toUint32(ctx, obj.get(ctx, 'length')).longValue();
                if (len.intValue() != len)
                    Utils.RangeError(ctx, 'Join length [' + len + '] exceeds the host system\'s maximum value');
                else if (len == 0)
                    return '';
                
                // build a String[] of parts to join:
                for (Integer k=0; k < len; k++) {
                    next = obj.get(ctx, String.valueOf(k));
                    parts.add(next == Utils.undefined || next == Utils.nul ? '' : Utils.toString(ctx, next));
                }
            }
            
            // now we "log-join" the parts, because for some reason Apex's built-in String.joinArray is slower -- log-join is awesome!
            String sep = argv.size() == 0 || argv[0] == null ? ',' : Utils.toString(ctx, argv[0]);
            // tracks the # of elements/intermediates relevant to the current "round":
            Integer upper = parts.size();
            // outer loop for approximately LOG (base 2) iterations:
            while (upper > 1) {
                // inner loop adjacently pairs up and concatenates the intermediate results:
                Integer i = 0; // write index
                Integer j = 0; // read index (1st element of current pair)
                // if we have a next pair of elements, then pair them up and advance to the next pair:
                while (j + 1 < upper) {
                    parts[i++] = parts[j] + sep + parts[j + 1];
                    j += 2;
                }
                // if we have a dangling element, then pass it into the next round:
                if (j < upper) {
                    parts[i] = parts[j];
                    // oops, we don't want our dangling element to get lopped off by the outer loop's
                    // next integer-division by 2, so bump upper up to the next even number in preparation
                    // for the next iteration -- think of the dangling element as a "remainder" from a 
                    // modulus(upper, 2) operation:
                    upper++;
                }
                // integer division; cut in half the # of elements we process in the next round:
                upper /= 2;
            }
            // hooray; our "simple" join procedure is done; the 1st element represents the final result:
            return parts[0];
        }
    }
    
    global class Pop extends Function {
        public Pop(Context ctx) {
            super(ctx, 'pop', 0);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Boolean isArray;
            PlainObject obj;
            if (thisArg != null && ((isArray = thisArg instanceof ArrayObject) || thisArg instanceof PlainObject)) {
                if (isArray) {
                    // optimized version for arrays:
                    ArrayObject arr = (ArrayObject) thisArg;
                    // we know every array has an own "length" data property:
                    PropertyDescrip lenDesc = arr.props.get('length');
                    // if the array length property has value 0 then we're done -- even if the length property is not writable, we won't be changing
                    // its value, so the spec's prescribed [[Put]] of 0 into "length" won't throw an error, and is essentially a no-op in this case:
                    if (arr.length == 0)
                        return null;
                        
                    String indx = String.valueOf(arr.length - 1);
                    PropertyDescrip elmtDesc = arr.props.get(indx);
                    // if the element is not an own configurable data property, then we must use the more generic [[Delete]] and [[Put]] methods:
                    if (elmtDesc == null || elmtDesc.isAccessor || !elmtDesc.configurable) {
                        Object elmtValue = arr.get(ctx, indx);
                        arr.deleteProperty(ctx, indx, true);
                        arr.put(ctx, 'length', Double.valueOf(arr.length - 1), true);
                        return elmtValue;
                    // else the element is an own configurable data property (most common case for arrays); we can further optimize this operation:
                    } else {
                        arr.props.remove(indx);
                        // if the length property is writable, then we can write the new length directly into it:
                        if (lenDesc.writable) {
                            arr.length = arr.length - 1;
                            lenDesc.value = (Double) arr.length;
                        // else we have to use the more generic [[Put]], which will probably throw an error in this case:
                        } else
                            arr.put(ctx, 'length', Double.valueOf(arr.length - 1), true);
                            
                        return elmtDesc.value;
                    }
                    
                } else
                    obj = (PlainObject) thisArg;
            } else
                obj = Utils.toObject(ctx, thisArg);
            
            // generic version for non-array objects:
            Double dlen = Utils.toUint32(ctx, obj.get(ctx, 'length'));
            if (dlen == 0) {
                // this will throw an error in some cases -- e.g. if "length" is not writable and has the value "undefined":
                obj.put(ctx, 'length', dlen, true);
                return null;
            }
            Double indx = dlen - 1;
            String sindx = String.valueOf(indx);
            Object elmt = obj.get(ctx, sindx);
            obj.deleteProperty(ctx, sindx, true);
            // TODO: the spec says to [[Put]] into length the value of sindx -- a String value -- but that seems silly. we'll put the number value
            // instead (see Mozilla and V8 engines):
            obj.put(ctx, 'length', dlen - 1, true);
            return elmt;
        }
    }
    
    global class Push extends Function {
        public Push(Context ctx) {
            super(ctx, 'push', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Boolean isArray;
            PlainObject obj;
            Long n;
            if (thisArg != null && ((isArray = thisArg instanceof ArrayObject) || thisArg instanceof PlainObject)) {
                if (isArray) {
                    ArrayObject arr = (ArrayObject) thisArg;
                    // if it's a array we can easily grab the length:
                    n = arr.length;
                    // other than getting the length, there's not much we can do here to optimize for array objects, since the spec requires [[Put]]
                    // calls for each new element. its is possible -- though very unlikely -- that these [[Put]] calls may hit accessors or non-
                    // writable properties that have been foolishly added to the Array and/or Object prototypes:
                    for (Object e: argv)
                        obj.put(ctx, String.valueOf(n++), e, true);
                    
                    PropertyDescrip lenDesc = arr.props.get('length');
                    // if we determine that our new length is valid to write, then write it directly into the existing descriptor:
                    if (lenDesc.writable && n <= Utils.Pow2_32_1) {
                        arr.length = n;
                        lenDesc.value = (Double) n;
                    // otherwise we need to invoke [[Put]], which may throw an error (e.g. not writable TypeError or RangeError):
                    } else
                        arr.put(ctx, 'length', (Double) n, true);
                    
                    return lenDesc.value;
                } else
                    obj = (PlainObject) thisArg;
            } else
                obj = Utils.toObject(ctx, thisArg);
            
            // here's the generic version for non-array objects:
            n = Utils.toUint32(ctx, obj.get(ctx, 'length')).longValue();
            for (Object e: argv)
                obj.put(ctx, String.valueOf(n++), e, true);
            
            Double dlen = n;
            obj.put(ctx, 'length', dlen, true);
            return dlen;
        }
    }
    
    global class Reverse extends Function {
        public Reverse(Context ctx) {
            super(ctx, 'reverse', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Boolean isArray;
            PlainObject obj;
            Long len;
            // note that middle and lower are guaranteed to always fit into a signed 32-bit int (though only just -- and we don't actually use 32-bit
            // ints  here, though we could), unlike upper and len which may exceed that and thus require the 64-bit Long type:
            Long middle, lower = 0;
            if (thisArg != null && ((isArray = thisArg instanceof ArrayObject) || thisArg instanceof PlainObject)) {
                if (isArray) {
                    ArrayObject arr = (ArrayObject) thisArg;
                    // if it's a array we can easily grab the length:
                    len = arr.length;
                    middle = len / 2;
                    
                    while (lower != middle) {
                        Long upper = len - lower - 1;
                        String upperP = String.valueOf(upper),
                               lowerP = String.valueOf(lower);
                    
                        // we start by assuming that upperP and lowerP are own data props on the array, which is by far the most common case for a
                        // not-too-sparse array:
                        PropertyDescrip upperDesc = arr.props.get(upperP),
                                        lowerDesc = arr.props.get(lowerP);
                                        
                        // we can take a super shortcut if the following assertion proves true: upper and lower are own writable data props:
                        if (upperDesc != null && lowerDesc != null && upperDesc.isAccessor == lowerDesc.isAccessor && !upperDesc.isAccessor 
                                && upperDesc.writable && lowerDesc.writable) {
                            upperDesc.value = lowerDesc.value;
                            lowerDesc.value = upperDesc.value;
                        // otherwise, implement more generic logic:
                        } else {
                            // if we didn't find an own property of either, then search proto for an inherited prop:
                            if (upperDesc == null)
                                upperDesc = arr.proto.getProperty(ctx, upperP);
                            if (lowerDesc == null)
                                lowerDesc = arr.proto.getProperty(ctx, lowerP);
                            
                            Object upperValue, lowerValue;
                            // get the values: in most cases these will be data props, and we can directly grab the values in those cases, deferring
                            // to [[Get]] in other cases:
                            if (upperDesc != null) {
                                if (upperDesc.isAccessor)
                                    upperValue = arr.get(ctx, upperP);
                                else
                                    upperValue = upperDesc.value;
                            }
                            if (lowerDesc != null) {
                                if (lowerDesc.isAccessor)
                                    lowerValue = arr.get(ctx, lowerP);
                                else
                                    lowerValue = lowerDesc.value;
                            }
                            
                            // use the generic [[Put]] and/or [[Delete]] methods to perform the swap, since we can't assume these are own own props
                            // or data props:
                            if (upperDesc != null)
                                obj.put(ctx, lowerP, upperValue, true);
                            else
                                obj.deleteProperty(ctx, lowerP, true);
                            
                            if (lowerDesc != null)
                                obj.put(ctx, upperP, lowerValue, true);
                            else
                                obj.deleteProperty(ctx, upperP, true);
                        }
                    }
                    
                    return arr;
                    
                } else
                    obj = (PlainObject) thisArg;
            } else
                obj = Utils.toObject(ctx, thisArg);
            
            // here's the generic version for non-array objects:
            len = Utils.toUint32(ctx, obj.get(ctx, 'length')).longValue();
            middle = len / 2;
            
            while (lower != middle) {
                Long upper = len - lower - 1;
                String upperP = String.valueOf(upper),
                       lowerP = String.valueOf(lower);
                Object lowerValue = obj.get(ctx, lowerP),
                       upperValue = obj.get(ctx, upperP);
                
                if (obj.hasProperty(ctx, upperP))
                    obj.put(ctx, lowerP, upperValue, true);
                else
                    obj.deleteProperty(ctx, lowerP, true);
                
                if (obj.hasProperty(ctx, lowerP))
                    obj.put(ctx, upperP, lowerValue, true);
                else
                    obj.deleteProperty(ctx, upperP, true);
            }
            
            return obj;
        }
    }
    
    /*
    global class Concat extends Function {
        public Concat(Context ctx) {
            super(ctx, 'concat', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            PlainObject o = Utils.toObject(ctx, thisArg);
            ArrayObject arr = new ArrayObject(ctx);
            
            
            
        }
    }
    */
    
    // 'sort' is also an Apex reserved word; what a surprise!
    global class SortArray extends Function {
        public SortArray(Context ctx) {
            super(ctx, 'sort', 1);
        }
        
        global override Object call(Context ctx, Object thisArg, Object[] argv) {
            Boolean isArray;
            if (thisArg == null || !((isArray = thisArg instanceof ArrayObject) || thisArg instanceof PlainObject))
                return thisArg;
            
            PlainObject arr = (PlainObject) thisArg;
            Boolean hasProto = arr.proto != null;
            Long len;
            if (isArray)
                len = ((ArrayObject) thisArg).length;
            else {   
                len = Utils.toUint32(ctx, arr.get(ctx, 'length')).longValue();
                if (len < 0)
                    Utils.TypeError(ctx, 'Object with negative length cannot be sorted');
            }
            
            if (len > len.intValue())
                // yeah, Apex (and Java) Lists have a max length dictated by a signed 32-bit int, i.e. (2^31 - 1). unfortunately ECMAScript specifies
                // its Array up to a length of an unsigned 32-bit int, i.e. (2^32 - 1). since we need the Apex List for compacted sorting, we'll have
                // to throw an error for Arrays with a length larger than what we can handle. in reality, due to interpretive overhead, you're not
                // going to want to sort anything within a few orders of magnitude of 2^31 elements...
                Utils.TypeError(ctx, (isArray ? 'Array' : 'Object') 
                        + ' with length greater than 2147483647 cannot be sorted due to host system limitations');

            // this will hold the elements post-compacting and sort:
            SortElmt[] compacted = new SortElmt[]{};
            // maps each element by its pre-sort index:
            Map<Integer, SortElmt> oldElmts = new Map<Integer, SortElmt>();
            SortElmt elmtTemplate = new SortElmt();
            Object cmpFunc = argv.size() == 0 ? null : argv[0];
            if (cmpFunc != null && cmpFunc instanceof Callable) {
                // we'll have a single dedicated vm for repeated execution of the custom comparator function:
                elmtTemplate.delegatorMachine = VirtualMachine.newDelegator(ctx, (Callable) cmpFunc);
                elmtTemplate.cmpArgv = new Object[2];
            }

            for (Integer i=0; i < len; i++) {
                String p = String.valueOf(i);
                PropertyDescrip prop = arr.getOwnProperty(ctx, p);
                SortElmt elmt = elmtTemplate.clone();
                if (prop == null && hasProto) {
                    elmt.inherited = true;
                    prop = arr.proto.getProperty(ctx, p);
                    if (prop == null)
                        continue;
                }
                
                if (prop.isAccessor || !prop.writable)
                    Utils.TypeError(ctx, (isArray ? 'Array' : 'Object')  + ' cannot be sorted because element at index ' + p 
                            + ' is ' + (prop.isAccessor ? 'an accessor' : 'not writable'));
                
                elmt.fromIndex = i;
                elmt.origName = p;
                elmt.origValue = prop.value;
                elmt.origProp = prop;
                oldElmts.put(i, elmt);
                compacted.add(elmt);
            }

            Boolean sparse = compacted.size() < len;
            if (sparse && !this.extensible)
                Utils.TypeError(ctx, (isArray ? 'Array' : 'Object') + ' cannot be sorted because it is both sparse and non-extensible');

            compacted.sort();
            Integer compLen = compacted.size();

            // use the compacted/sorted elements to update this array to the correct sort order -- this is trivial and efficient in the case of a
            // non-sparse array:
            if (!sparse) {
                for (Integer i=0; i < compLen; i++) {
                    oldElmts.get(i).origProp.value = compacted[i].origValue;
                }
            } else {
                for (Integer i=0; i < compLen; i++) {
                    SortElmt oldElmt = oldElmts.get(i);
                    SortElmt newElmt = compacted[i];
                    
                    // if newElmt is coming from from the "sparse gap", then the property at its original index should ideally be vacatable to allow
                    // it to move cleanly into the compacted range:
                    if (newElmt.fromIndex >= compLen) {
                        // try to vacate newElmt's original index -- we can do so only if it's configurable AND not inherited:
                        if (newElmt.origProp.configurable && newElmt.inherited != true) {
                            if (isArray)
                                arr.props.remove(newElmt.origName);
                            else
                                arr.deleteProperty(ctx, newElmt.origName, false);
                        }
                        // else it's not vacatable. we'll just have to settle for leaving the damned thing in place; fallthrough to write (i.e.
                        // duplicate) the newElmt's value into oldElmt's original index...
                    }
                    // else, newElmt is not coming from the "sparse gap"...
                    
                    // write newElmt's original value into its new destination index -- if oldElmt exists, then it's guaranteed to be writable data
                    // prop because of our prior checks. however, it may be inherited. use [[DefinedOwnProperty]] if oldElmt does not exist or is
                    // inherited:
                    if (oldElmt == null || oldElmt.inherited == true) {
                        PropertyDescrip newDesc = PropertyDescrip.DataAllPrivs.clone();
                        newDesc.value = newElmt.origValue;
                        arr.defineOwnProperty(ctx, String.valueOf(i), newDesc, false); // , postElmt.prop);
                    // else, oldElmt is an existing own data prop -- we can do a simple direct value write into it (shortcut):
                    } else
                        oldElmt.origProp.value = newElmt.origValue;
                    
                }
            }
            
            return arr;
        }
    }
    
    // helper class for SortArray[[Call]], since Apex doesn't have a proper comparator function argument for its List.sort method:
    global class SortElmt implements Comparable {
        // these will be non-null if there's a custom comparator function:
        VirtualMachine delegatorMachine;
        Object[] cmpArgv;
        
        Boolean inherited;
        Integer fromIndex;
        String origName;
        Object origValue;
        PropertyDescrip origProp;
        
        global Integer compareTo(Object oy) {
            SortElmt y = (SortElmt) oy;
            if (this.origValue == null || y.origValue == null)
                if (this.origValue == y.origValue)
                    return 0;
                else
                    return this.origValue == null ? -1 : 1;
            
            if (delegatorMachine != null) {
                cmpArgv[0] = this.origValue;
                cmpArgv[1] = y.origValue;
                Object cmpVal = VirtualMachine.execDelegate(delegatorMachine, null, cmpArgv);
                if (cmpVal != null && cmpVal instanceof Double)
                    return ((Double) cmpVal).intValue();
                else
                    return 0;
                
            } else {
                Context hostCtx = delegatorMachine.ctx.parent;
                return Utils.toString(hostCtx, this.origValue).compareTo(Utils.toString(hostCtx, y.origValue));
            }
        }
    }
    
}