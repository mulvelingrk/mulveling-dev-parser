/*
 * Mike Ulveling
 * 
 * ECMAScript null value; a singleton that does not extend PlainObject
 */
global class NullSingleton {
    private NullSingleton() {}
    
    // it would be great if Apex dispatched toString at appropriate times, e.g. in '+' operations, but it doesn't, so this override is useless:
    global override String toString() {
        return 'null';
    }
    
    global static NullSingleton NUL = new NullSingleton();
}