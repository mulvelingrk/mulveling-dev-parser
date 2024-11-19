/*
 * Mike Ulveling
 */
global abstract class PrimitiveObject extends PlainObject {
    public Object primitiveValue;
    
    public PrimitiveObject(Context ctx, String className, Object primitiveValue) {
        super(ctx, className);
        this.primitiveValue = primitiveValue;
    }
}