/* Reference: the operation compiled inline, built per function with
   -DNAME and -DOP, for the configurations with the divider or
   multiplier.  */
__attribute__((noipa)) unsigned NAME (unsigned a, unsigned b) { return OP; }
