global class SetContext extends GetContext {
	// Before Accessor.set is called, runtime logic sets newVal to the right-hand side value of the assignment expression, performing 
	// automatic type conversion if this rhs of assignment is imperfectly compatible with the lhs. During execution of Accessor.set, the 
	// logic may update newVal. After Accessor.set finishes, runtime logic will pickup newVal to update the property's internal value, 
	// performing automatic type checking/conversion if specified by Accessor.typeChecking == true:
    global Value newVal;
}