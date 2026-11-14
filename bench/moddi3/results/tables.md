# 64-bit divide and remainder, estimated cycles per call

Made by bench/moddi3/reproduce.sh, with patches/gcc as of
microblaze-testsuite 548ad83 (the libgcc series only) and:

```
binutils 19c3a4c423b1251c4662d3bec7ff818ce29f57f7 2026-11-02
gcc df809a029f522bc22265ad5ec0eb98f46421030e 2026-11-07
newlib b097f95233d26da7af6887798297d1efadb75370 2026-10-30
qemu 10.2.4
```

Each cell is the mean over 4701 operand pairs, then for the cycle
tables the slowest single call in brackets.  The unsigned routines'
operands are never negative; see gen.c.
"Upstream C" is libgcc2.c as gcc has it.
For __moddi3 it is what deleting moddi3.S would give; for the other
three it is what libgcc builds today.  "No-divider code" is the
same with TARGET_HAS_NO_HW_DIVIDE, its shift-and-subtract division.
"+ back end" is compiled by a gcc with the back-end series.

## Instructions per call, big-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Original Xilinx assembly | did not finish | | | |
| Assembly fix, upstream `moddi3.S` | 520.5 | 520.5 | 520.5 | 520.5 |
| Improved assembly, `moddi3-new.S` | 218.0 | 218.0 | 218.0 | 218.0 |
| Upstream C, `libgcc2.c` | 1347.8 | 900.2 | 899.9 | 89.7 |
| Upstream C + back end | 1347.8 | 900.2 | 899.9 | 89.7 |
| Upstream C, no-divider code | 1328.6 | 330.4 | 297.7 | 297.7 |
| Upstream C, no-divider code + back end | 435.9 | 257.5 | 220.3 | 220.3 |
| libgcc series | 455.0 | 273.3 | 236.9 | 89.7 |
| libgcc series + back end | 343.9 | 215.2 | 178.3 | 89.7 |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1307.6 | 873.2 | 872.8 | 68.0 |
| Upstream C + back end | 1307.6 | 873.2 | 872.8 | 68.0 |
| Upstream C, no-divider code | 1304.4 | 315.8 | 275.7 | 275.7 |
| Upstream C, no-divider code + back end | 415.2 | 237.8 | 197.8 | 197.8 |
| libgcc series | 439.9 | 256.9 | 222.6 | 68.0 |
| libgcc series + back end | 351.6 | 221.2 | 186.9 | 68.0 |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1301.3 | 901.7 | 901.5 | 86.4 |
| Upstream C + back end | 1301.3 | 901.7 | 901.5 | 86.4 |
| Upstream C, no-divider code | 1403.5 | 374.0 | 309.5 | 309.5 |
| Upstream C, no-divider code + back end | 500.6 | 257.7 | 229.2 | 229.2 |
| libgcc series | 1310.7 | 336.4 | 305.5 | 86.4 |
| libgcc series + back end | 412.2 | 258.5 | 226.9 | 86.4 |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1263.2 | 875.5 | 875.4 | 58.0 |
| Upstream C + back end | 1263.2 | 875.5 | 875.4 | 58.0 |
| Upstream C, no-divider code | 1372.2 | 321.3 | 294.2 | 294.2 |
| Upstream C, no-divider code + back end | 482.0 | 242.1 | 211.8 | 211.8 |
| libgcc series | 1289.9 | 323.5 | 288.9 | 58.0 |
| libgcc series + back end | 395.2 | 240.4 | 212.5 | 58.0 |

## Estimated cycles, 5-stage (C_AREA_OPTIMIZED=0), no branch target cache, big-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 700.2 (862) | 700.2 (862) | 700.2 (862) | 700.2 (862) |
| Improved assembly, `moddi3-new.S` | 257.5 (903) | 257.5 (903) | 257.5 (903) | 257.5 (903) |
| Upstream C, `libgcc2.c` | 1784.6 (4133) | 1222.4 (3448) | 1222.0 (3448) | 171.8 (297) |
| Upstream C + back end | 1784.6 (4133) | 1222.4 (3448) | 1222.0 (3448) | 171.8 (297) |
| Upstream C, no-divider code | 1429.4 (5577) | 370.5 (1316) | 333.2 (1265) | 333.2 (1265) |
| Upstream C, no-divider code + back end | 545.8 (1418) | 314.2 (1067) | 271.8 (1003) | 271.8 (1003) |
| libgcc series | 530.4 (1348) | 310.0 (931) | 268.6 (870) | 171.8 (297) |
| libgcc series + back end | 444.8 (1043) | 277.3 (811) | 235.7 (751) | 171.8 (297) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1735.6 (4106) | 1189.4 (3422) | 1189.0 (3422) | 145.5 (271) |
| Upstream C + back end | 1735.6 (4106) | 1189.4 (3422) | 1189.0 (3422) | 145.5 (271) |
| Upstream C, no-divider code | 1402.2 (5648) | 352.5 (1317) | 308.2 (1259) | 308.2 (1259) |
| Upstream C, no-divider code + back end | 521.8 (1413) | 290.9 (1055) | 246.6 (990) | 246.6 (990) |
| libgcc series | 513.3 (1349) | 290.9 (925) | 252.3 (867) | 145.5 (271) |
| libgcc series + back end | 433.5 (1028) | 263.7 (796) | 225.2 (738) | 145.5 (271) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1717.2 (4047) | 1222.9 (3456) | 1222.8 (3456) | 168.0 (280) |
| Upstream C + back end | 1717.2 (4047) | 1222.9 (3456) | 1222.8 (3456) | 168.0 (280) |
| Upstream C, no-divider code | 1517.6 (5776) | 415.3 (1580) | 345.4 (1278) | 345.4 (1278) |
| Upstream C, no-divider code + back end | 630.5 (1751) | 315.5 (1071) | 281.5 (1017) | 281.5 (1017) |
| libgcc series | 1397.7 (5527) | 377.2 (1330) | 339.9 (1275) | 168.0 (280) |
| libgcc series + back end | 523.5 (1480) | 323.5 (1130) | 286.4 (1075) | 168.0 (280) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1671.1 (4021) | 1191.1 (3433) | 1191.0 (3433) | 134.4 (243) |
| Upstream C + back end | 1671.1 (4021) | 1191.1 (3433) | 1191.0 (3433) | 134.4 (243) |
| Upstream C, no-divider code | 1489.2 (5914) | 359.1 (1331) | 327.6 (1281) | 327.6 (1281) |
| Upstream C, no-divider code + back end | 607.1 (1731) | 295.8 (1065) | 261.2 (1011) | 261.2 (1011) |
| libgcc series | 1374.1 (5601) | 360.8 (1334) | 321.8 (1276) | 134.4 (243) |
| libgcc series + back end | 503.8 (1484) | 302.5 (1126) | 270.2 (1076) | 134.4 (243) |

## Estimated cycles, 5-stage, perfect branch target cache, big-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 520.5 (726) | 520.5 (726) | 520.5 (726) | 520.5 (726) |
| Improved assembly, `moddi3-new.S` | 218.0 (807) | 218.0 (807) | 218.0 (807) | 218.0 (807) |
| Upstream C, `libgcc2.c` | 1347.8 (3127) | 900.2 (2574) | 899.9 (2574) | 160.7 (283) |
| Upstream C + back end | 1347.8 (3127) | 900.2 (2574) | 899.9 (2574) | 160.7 (283) |
| Upstream C, no-divider code | 1328.6 (5292) | 330.4 (1176) | 297.7 (1129) | 297.7 (1129) |
| Upstream C, no-divider code + back end | 435.9 (1129) | 257.5 (861) | 220.3 (806) | 220.3 (806) |
| libgcc series | 455.0 (1217) | 273.3 (854) | 236.9 (801) | 160.7 (283) |
| libgcc series + back end | 343.9 (837) | 215.2 (663) | 178.3 (610) | 160.7 (283) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1307.6 (3117) | 873.2 (2566) | 872.8 (2566) | 136.4 (258) |
| Upstream C + back end | 1307.6 (3117) | 873.2 (2566) | 872.8 (2566) | 136.4 (258) |
| Upstream C, no-divider code | 1304.4 (5361) | 315.8 (1178) | 275.7 (1127) | 275.7 (1127) |
| Upstream C, no-divider code + back end | 415.2 (1125) | 237.8 (852) | 197.8 (794) | 197.8 (794) |
| libgcc series | 439.9 (1219) | 256.9 (850) | 222.6 (799) | 136.4 (258) |
| libgcc series + back end | 351.6 (898) | 221.2 (721) | 186.9 (670) | 136.4 (258) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1301.3 (3070) | 901.7 (2583) | 901.5 (2583) | 157.3 (259) |
| Upstream C + back end | 1301.3 (3070) | 901.7 (2583) | 901.5 (2583) | 157.3 (259) |
| Upstream C, no-divider code | 1403.5 (5491) | 374.0 (1436) | 309.5 (1143) | 309.5 (1143) |
| Upstream C, no-divider code + back end | 500.6 (1337) | 257.7 (864) | 229.2 (819) | 229.2 (819) |
| libgcc series | 1310.7 (5300) | 336.4 (1186) | 305.5 (1140) | 157.3 (259) |
| libgcc series + back end | 412.2 (1130) | 258.5 (863) | 226.9 (817) | 157.3 (259) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1263.2 (3062) | 875.5 (2578) | 875.4 (2578) | 126.4 (231) |
| Upstream C + back end | 1263.2 (3062) | 875.5 (2578) | 875.4 (2578) | 126.4 (231) |
| Upstream C, no-divider code | 1372.2 (5564) | 321.3 (1189) | 294.2 (1146) | 294.2 (1146) |
| Upstream C, no-divider code + back end | 482.0 (1325) | 242.1 (860) | 211.8 (813) | 211.8 (813) |
| libgcc series | 1289.9 (5374) | 323.5 (1192) | 288.9 (1141) | 126.4 (231) |
| libgcc series + back end | 395.2 (1132) | 240.4 (859) | 212.5 (816) | 126.4 (231) |

## Estimated cycles, 3-stage (C_AREA_OPTIMIZED=1), big-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 708.2 (870) | 708.2 (870) | 708.2 (870) | 708.2 (870) |
| Improved assembly, `moddi3-new.S` | 257.5 (903) | 257.5 (903) | 257.5 (903) | 257.5 (903) |
| Upstream C, `libgcc2.c` | 1845.5 (4222) | 1294.0 (3554) | 1293.7 (3554) | 204.2 (346) |
| Upstream C + back end | 1845.5 (4222) | 1294.0 (3554) | 1293.7 (3554) | 204.2 (346) |
| Upstream C, no-divider code | 1450.7 (5599) | 423.3 (1468) | 379.0 (1408) | 379.0 (1408) |
| Upstream C, no-divider code + back end | 562.5 (1436) | 335.4 (1090) | 280.8 (1011) | 280.8 (1011) |
| libgcc series | 547.1 (1366) | 347.4 (1016) | 294.0 (940) | 204.2 (346) |
| libgcc series + back end | 458.8 (1059) | 294.4 (831) | 241.1 (756) | 204.2 (346) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1791.9 (4191) | 1258.7 (3528) | 1258.4 (3528) | 175.2 (319) |
| Upstream C + back end | 1791.9 (4191) | 1258.7 (3528) | 1258.4 (3528) | 175.2 (319) |
| Upstream C, no-divider code | 1422.8 (5670) | 404.2 (1471) | 345.3 (1400) | 345.3 (1400) |
| Upstream C, no-divider code + back end | 533.7 (1427) | 307.2 (1074) | 249.4 (992) | 249.4 (992) |
| libgcc series | 525.2 (1363) | 323.5 (1007) | 275.2 (936) | 175.2 (319) |
| libgcc series + back end | 462.3 (1105) | 295.7 (877) | 247.4 (806) | 175.2 (319) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1779.8 (4146) | 1295.0 (3569) | 1294.8 (3569) | 197.9 (323) |
| Upstream C + back end | 1779.8 (4146) | 1295.0 (3569) | 1294.8 (3569) | 197.9 (323) |
| Upstream C, no-divider code | 1546.3 (5808) | 509.1 (1986) | 398.6 (1429) | 398.6 (1429) |
| Upstream C, no-divider code + back end | 644.5 (1767) | 335.1 (1094) | 295.4 (1031) | 295.4 (1031) |
| libgcc series | 1425.6 (5557) | 436.4 (1490) | 387.3 (1420) | 197.9 (323) |
| libgcc series + back end | 540.1 (1498) | 344.4 (1153) | 296.9 (1085) | 197.9 (323) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1730.3 (4118) | 1261.1 (3546) | 1260.9 (3546) | 158.3 (279) |
| Upstream C + back end | 1730.3 (4118) | 1261.1 (3546) | 1260.9 (3546) | 158.3 (279) |
| Upstream C, no-divider code | 1509.8 (5936) | 412.3 (1488) | 378.0 (1432) | 378.0 (1432) |
| Upstream C, no-divider code + back end | 619.0 (1745) | 313.3 (1086) | 273.2 (1023) | 273.2 (1023) |
| libgcc series | 1398.8 (5627) | 416.0 (1492) | 366.8 (1422) | 158.3 (279) |
| libgcc series + back end | 515.8 (1498) | 318.2 (1145) | 280.5 (1087) | 158.3 (279) |

## Data-hazard stalls, 5-stage, big-endian

Mean cycles per call that UG984's data hazards add to either 5-stage figure, low and high bound.

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 |
| Improved assembly, `moddi3-new.S` | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 |
| Upstream C, `libgcc2.c` | 1.0-1.1 | 3.5-3.7 | 3.5-3.7 | 7.2-8.0 |
| Upstream C + back end | 1.0-1.1 | 3.5-3.7 | 3.5-3.7 | 7.2-8.0 |
| Upstream C, no-divider code | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 0.0-0.0 |
| Upstream C, no-divider code + back end | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 0.0-0.0 |
| libgcc series | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 7.2-8.0 |
| libgcc series + back end | 2.0-3.3 | 1.3-1.5 | 0.0-0.0 | 7.2-8.0 |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1.3-1.7 | 3.1-3.4 | 3.1-3.4 | 6.2-6.8 |
| Upstream C + back end | 1.3-1.7 | 3.1-3.4 | 3.1-3.4 | 6.2-6.8 |
| Upstream C, no-divider code | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 0.0-0.0 |
| Upstream C, no-divider code + back end | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 0.0-0.0 |
| libgcc series | 2.0-3.3 | 2.0-2.2 | 0.0-0.0 | 6.2-6.8 |
| libgcc series + back end | 2.0-3.3 | 2.0-2.2 | 0.0-0.0 | 6.2-6.8 |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 2.3-3.9 | 4.7-5.5 | 4.7-5.5 | 6.4-7.2 |
| Upstream C + back end | 2.3-3.9 | 4.7-5.5 | 4.7-5.5 | 6.4-7.2 |
| Upstream C, no-divider code | 2.4-4.8 | 2.1-2.3 | 0.0-0.0 | 0.0-0.0 |
| Upstream C, no-divider code + back end | 2.0-3.3 | 2.2-2.4 | 0.0-0.0 | 0.0-0.0 |
| libgcc series | 2.0-4.0 | 2.0-2.8 | 0.0-0.0 | 6.4-7.2 |
| libgcc series + back end | 1.3-2.6 | 1.3-1.5 | 0.0-0.0 | 6.4-7.2 |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1.9-3.3 | 4.3-5.1 | 4.3-5.1 | 6.2-7.0 |
| Upstream C + back end | 1.9-3.3 | 4.3-5.1 | 4.3-5.1 | 6.2-7.0 |
| Upstream C, no-divider code | 1.3-2.6 | 2.4-2.6 | 0.7-0.7 | 0.7-0.7 |
| Upstream C, no-divider code + back end | 1.3-2.6 | 2.2-2.4 | 0.7-0.7 | 0.7-0.7 |
| libgcc series | 1.3-2.6 | 1.3-1.5 | 0.9-0.9 | 6.2-7.0 |
| libgcc series + back end | 1.3-2.6 | 1.3-1.5 | 0.4-0.4 | 6.2-7.0 |

