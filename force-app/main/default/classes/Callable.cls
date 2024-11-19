/*
 * Mike Ulveling
 */
global interface Callable {
    Object call(Context ctx, Object thisBinding, Object[] argv);
}