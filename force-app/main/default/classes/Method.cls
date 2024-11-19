/* 
 * Method is a base class that is extended to provide the implementation for a method. Subclasses may optionally use DynamicReturnType as 
 * their base, if they need to dynamically determine the method return type (e.g. IF, CASE logic functions).
 */
global interface Method {
    Value invoke(InvocationContext context);
}