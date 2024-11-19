/*
 * Optionally use this as a base interface for method implementations, instead of Method
*/
global interface DynamicReturnType extends Method {
    // argc are physical arguments, with their data typeas as calculated at compile-time. This method should throw a SemanticError 
    // if it doesn't like the argc for any reason -- though argc is guaranteed to match func. formatArgs, this resolver may need to 
    // impose additional logical validation, e.g. enforce an even-number of Object argc elements for a Object{2,} formal arg slot, 
    // etc:
    DataDesc resolveReturnType(DataDesc[] argc);
}