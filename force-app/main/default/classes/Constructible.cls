/*
 * Mike Ulveling
 */
global interface Constructible extends Callable {
    Object construct(Context ctx, Object[] argv);
}