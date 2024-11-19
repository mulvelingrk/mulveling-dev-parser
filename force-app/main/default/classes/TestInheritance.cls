/*
 * Mike Ulveling
 */
@isTest
global class TestInheritance {
    @isTest
    static void testCore() {
        Context ctx = new Context();
        PlainObject po = new PlainObject(ctx);
        
        // Object.prototype === {}.__proto__
        System.assert(getOwnDataProp(ctx.ObjectConstruct, 'prototype') === po.proto);
        System.assertEquals('Object', po.className);
        
        // Object.__proto__ !== {}.__proto__
        System.assert(ctx.ObjectConstruct.proto !== po.proto);
        // Object.__proto__.__proto__ === {}.__proto__
        System.assert(ctx.ObjectConstruct.proto.proto === po.proto);
        // Object.__proto__ === Function.__proto__ === Function.prototype
        System.assert(ctx.ObjectConstruct.proto === ctx.FunctionConstruct.proto);
        System.assert(ctx.ObjectConstruct.proto === getOwnDataProp(ctx.FunctionConstruct, 'prototype'));
        // ({}).__proto__ === Object.prototype
        System.assert(po.proto === ctx.ObjectProto);
        System.assert(po.proto === getOwnDataProp(ctx.ObjectConstruct, 'prototype'));
        // !! note that, in a slight break from spec, we use the ECMAScript value undefined instead of ECMAScript null to terminate prototype chains:
        // ({}).__proto__.__proto__ === null
        System.assert(po.proto.proto == null);
        // ({}).__proto__.hasOwnProperty('constructor') && ({}).__proto__.constructor === Object
        System.assert(getOwnDataProp(po.proto, 'constructor') === ctx.ObjectConstruct);
    
        Function objectFunc = ctx.ObjectConstruct;
        // Object.__proto__ === Function.prototype
        System.assert(objectFunc.proto != null && objectFunc.proto instanceof Function.EmptyFunc && objectFunc.proto === ctx.FunctionProto);
        // Object.__proto__.__proto__ === Object.prototype
        System.assert(objectFunc.proto.proto === ctx.ObjectProto);
        // !! note that, in a slight break from spec, we use the ECMAScript value undefined instead of ECMAScript null to terminate prototype chains:
        // Object.__proto__.__proto__.__proto__ === null
        System.assert(objectFunc.proto.proto.proto == null);
        // Object.prototype === {}.__proto__
        System.assert(getOwnDataProp(objectFunc, 'prototype') === ctx.ObjectProto);
        System.assert(getOwnDataProp(objectFunc, 'prototype') === po.proto);
        
        TestFunction testFunc = new TestFunction(ctx);
        // (function(){}).__proto__ === Function.__proto__ === Function.prototype
        System.assert(testFunc.proto === ctx.FunctionProto);
        System.assert(testFunc.proto === ctx.FunctionConstruct.proto);
        System.assert(testFunc.proto != null && testFunc.proto instanceof Function.EmptyFunc);
        // (function(){}).__proto__.hasOwnProperty('constructor') && (function(){}).__proto__.constructor === Function
        System.assert(getOwnDataProp(testFunc.proto, 'constructor') === ctx.FunctionConstruct);
        // ensure that each function instance has its own "prototype" that is a new PlainObject():
        // (function(){}).prototype !== ({}).__proto__ && (function(){}).prototype.__proto__ === ({}).__proto__
        System.assert(getOwnDataProp(testFunc, 'prototype') !== po.proto);
        System.assert(((PlainObject) getOwnDataProp(testFunc, 'prototype')).proto === po.proto);
        
        // the Empty func (i.e. Function.Prototype, a.k.a. Function.__proto__) has an internal [[proto]] that is exactly ctx.ObjectProto:
        Function emptyFunc = ctx.FunctionProto;
        // Function.__proto__.__proto__ === ({}).__proto__
        System.assert(emptyFunc.proto === po.proto);
        // the Empty func does not have a "prototype" property defined:
        assertNotHasOwnProp(emptyFunc, 'prototype');
        
        PlainObject plainErr = new Error(ctx, 'foo');
        PlainObject typeErr = new TypeError(ctx, 'bar');
        PlainObject refErr = new ReferenceError(ctx, 'baz');
        
        System.assert('Error' == getOwnDataProp(plainErr.proto, 'name'));
        System.assert('' == getOwnDataProp(plainErr.proto, 'message'));
        System.assert('foo' == getOwnDataProp(plainErr, 'message'));
        System.assertEquals('Error', plainErr.className);
        System.assert('TypeError' == getOwnDataProp(typeErr.proto, 'name'));
        assertNotHasOwnProp(typeErr.proto, 'message');
        System.assert('bar' == getOwnDataProp(typeErr, 'message'));
        System.assertEquals('Error', typeErr.className);
        System.assert('ReferenceError' == getOwnDataProp(refErr.proto, 'name'));
        assertNotHasOwnProp(refErr.proto, 'message');
        System.assert('baz' == getOwnDataProp(refErr, 'message'));
        System.assertEquals('Error', refErr.className);
        
        // new Error('foo').__proto__ === Error.prototype
        System.assert(plainErr.proto === getOwnDataProp(ctx.ErrorConstruct, 'prototype'));
        System.assert(plainErr.proto === ctx.ErrorProto);
        // new Error('foo').__proto__.__proto__ === {}.__proto__
        System.assert(plainErr.proto.proto === ctx.ObjectProto);
        
        // new TypeError('bar').__proto__ === TypeError.prototype
        System.assert(typeErr.proto === getOwnDataProp(ctx.TypeErrorConstruct, 'prototype'));
        System.assert(typeErr.proto === ctx.TypeErrorProto);
        // new TypeError('bar').__proto__.__proto__ === Error.prototype
        System.assert(typeErr.proto.proto === ctx.ErrorProto);
        // new TypeError('bar').__proto__.__proto__.__proto__ === Object.prototype
        System.assert(typeErr.proto.proto.proto === ctx.ObjectProto);
        
        // new ReferenceError('baz').__proto__ === ReferenceError
        System.assert(refErr.proto === getOwnDataProp(ctx.ReferenceErrorConstruct, 'prototype'));
        System.assert(refErr.proto === ctx.ReferenceErrorProto);
        // new ReferenceError('baz').__proto__.__proto__ === Error.prototype
        System.assert(refErr.proto.proto === ctx.ErrorProto);
        // new ReferenceError('baz').__proto__.__proto__.__proto__ === Object.prototype
        System.assert(refErr.proto.proto.proto === ctx.ObjectProto);
        
    }
    
    static Object getOwnDataProp(PlainObject po, String name) {
        PropertyDescrip pd = po.props.get(name);
        return pd.value;
    }
    
    static void assertNotHasOwnProp(PlainObject po, String name) {
        System.assert(null == po.props.get(name), 'Expected object to not have own property ' + name);
    }
    
    global class TestFunction extends Function {
        TestFunction(Context ctx) {
            super(ctx, 'TestFunction', 0, new PlainObject(ctx));
        }
        
        global override Object call(Context ctx, Object thisBinding, Object[] argv) { return null; }
    }
}