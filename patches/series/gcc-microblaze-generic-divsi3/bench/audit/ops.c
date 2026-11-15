/* Compiled once per variant with -DV=name and the variant's flags.  */
#define CAT2(a,b) a##_##b
#define CAT(a,b) CAT2(a,b)
__attribute__((noipa)) unsigned CAT(V,div)  (unsigned a, unsigned b) { return (int) a / (int) b; }
__attribute__((noipa)) unsigned CAT(V,mod)  (unsigned a, unsigned b) { return (int) a % (int) b; }
__attribute__((noipa)) unsigned CAT(V,udiv) (unsigned a, unsigned b) { return a / b; }
__attribute__((noipa)) unsigned CAT(V,umod) (unsigned a, unsigned b) { return a % b; }
__attribute__((noipa)) unsigned CAT(V,mul)  (unsigned a, unsigned b) { return a * b; }
