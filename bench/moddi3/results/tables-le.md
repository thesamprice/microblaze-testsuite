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

## Instructions per call, little-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Original Xilinx assembly | did not finish | | | |
| Assembly fix, upstream `moddi3.S` | 520.5 | 520.5 | 520.5 | 520.5 |
| Improved assembly, `moddi3-new.S` | 218.0 | 218.0 | 218.0 | 218.0 |
| Upstream C, `libgcc2.c` | 1348.5 | 899.6 | 899.3 | 88.2 |
| Upstream C + back end | 1348.5 | 899.6 | 899.3 | 88.2 |
| Upstream C, no-divider code | 1331.2 | 333.3 | 298.4 | 298.4 |
| Upstream C, no-divider code + back end | 436.9 | 258.3 | 221.0 | 221.0 |
| libgcc series | 456.0 | 274.2 | 237.7 | 88.2 |
| libgcc series + back end | 345.0 | 216.0 | 179.3 | 88.2 |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1305.1 | 873.0 | 872.7 | 68.3 |
| Upstream C + back end | 1305.1 | 873.0 | 872.7 | 68.3 |
| Upstream C, no-divider code | 1302.7 | 314.2 | 276.2 | 276.2 |
| Upstream C, no-divider code + back end | 416.2 | 239.1 | 199.1 | 199.1 |
| libgcc series | 440.2 | 257.2 | 222.9 | 68.3 |
| libgcc series + back end | 351.9 | 221.5 | 187.2 | 68.3 |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1302.6 | 900.5 | 900.3 | 85.2 |
| Upstream C + back end | 1302.6 | 900.5 | 900.3 | 85.2 |
| Upstream C, no-divider code | 1405.2 | 341.8 | 307.9 | 307.9 |
| Upstream C, no-divider code + back end | 502.3 | 259.1 | 225.5 | 225.5 |
| libgcc series | 1311.6 | 337.4 | 306.5 | 85.2 |
| libgcc series + back end | 413.2 | 259.5 | 227.9 | 85.2 |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1261.1 | 872.5 | 872.3 | 59.0 |
| Upstream C + back end | 1261.1 | 872.5 | 872.3 | 59.0 |
| Upstream C, no-divider code | 1376.0 | 325.8 | 292.3 | 292.3 |
| Upstream C, no-divider code + back end | 483.8 | 244.5 | 210.9 | 210.9 |
| libgcc series | 1290.9 | 324.5 | 289.0 | 59.0 |
| libgcc series + back end | 396.3 | 241.5 | 212.6 | 59.0 |

## Estimated cycles, 5-stage (C_AREA_OPTIMIZED=0), no branch target cache, little-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 700.2 (862) | 700.2 (862) | 700.2 (862) | 700.2 (862) |
| Improved assembly, `moddi3-new.S` | 257.5 (903) | 257.5 (903) | 257.5 (903) | 257.5 (903) |
| Upstream C, `libgcc2.c` | 1785.3 (4133) | 1221.8 (3448) | 1221.5 (3448) | 169.9 (295) |
| Upstream C + back end | 1785.3 (4133) | 1221.8 (3448) | 1221.5 (3448) | 169.9 (295) |
| Upstream C, no-divider code | 1431.9 (5580) | 373.1 (1322) | 333.5 (1266) | 333.5 (1266) |
| Upstream C, no-divider code + back end | 546.9 (1419) | 314.5 (1068) | 272.3 (1005) | 272.3 (1005) |
| libgcc series | 531.7 (1350) | 310.4 (930) | 268.9 (870) | 169.9 (295) |
| libgcc series + back end | 446.1 (1045) | 277.7 (810) | 236.2 (750) | 169.9 (295) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1732.9 (4103) | 1189.8 (3424) | 1189.4 (3424) | 145.5 (272) |
| Upstream C + back end | 1732.9 (4103) | 1189.8 (3424) | 1189.4 (3424) | 145.5 (272) |
| Upstream C, no-divider code | 1400.7 (5647) | 351.1 (1318) | 308.8 (1262) | 308.8 (1262) |
| Upstream C, no-divider code + back end | 522.9 (1414) | 292.6 (1059) | 248.3 (996) | 248.3 (996) |
| libgcc series | 513.8 (1351) | 291.1 (926) | 252.6 (868) | 145.5 (272) |
| libgcc series + back end | 434.1 (1030) | 264.0 (797) | 225.5 (739) | 145.5 (272) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1718.5 (4046) | 1221.5 (3454) | 1221.3 (3454) | 166.7 (277) |
| Upstream C + back end | 1718.5 (4046) | 1221.5 (3454) | 1221.3 (3454) | 166.7 (277) |
| Upstream C, no-divider code | 1519.5 (5779) | 383.3 (1337) | 343.3 (1277) | 343.3 (1277) |
| Upstream C, no-divider code + back end | 632.4 (1755) | 316.4 (1072) | 277.0 (1011) | 277.0 (1011) |
| libgcc series | 1398.6 (5529) | 378.2 (1331) | 340.9 (1276) | 166.7 (277) |
| libgcc series + back end | 524.4 (1482) | 324.5 (1131) | 287.5 (1076) | 166.7 (277) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1669.2 (4019) | 1188.1 (3431) | 1188.0 (3431) | 134.9 (245) |
| Upstream C + back end | 1669.2 (4019) | 1188.1 (3431) | 1188.0 (3431) | 134.9 (245) |
| Upstream C, no-divider code | 1493.2 (5919) | 363.5 (1336) | 325.7 (1280) | 325.7 (1280) |
| Upstream C, no-divider code + back end | 609.1 (1735) | 298.1 (1067) | 259.9 (1010) | 259.9 (1010) |
| libgcc series | 1375.2 (5602) | 361.8 (1335) | 321.9 (1276) | 134.9 (245) |
| libgcc series + back end | 505.3 (1485) | 303.6 (1127) | 270.3 (1076) | 134.9 (245) |

## Estimated cycles, 5-stage, perfect branch target cache, little-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 520.5 (726) | 520.5 (726) | 520.5 (726) | 520.5 (726) |
| Improved assembly, `moddi3-new.S` | 218.0 (807) | 218.0 (807) | 218.0 (807) | 218.0 (807) |
| Upstream C, `libgcc2.c` | 1348.5 (3127) | 899.6 (2574) | 899.3 (2574) | 159.2 (283) |
| Upstream C + back end | 1348.5 (3127) | 899.6 (2574) | 899.3 (2574) | 159.2 (283) |
| Upstream C, no-divider code | 1331.2 (5295) | 333.3 (1182) | 298.4 (1129) | 298.4 (1129) |
| Upstream C, no-divider code + back end | 436.9 (1130) | 258.3 (861) | 221.0 (806) | 221.0 (806) |
| libgcc series | 456.0 (1218) | 274.2 (853) | 237.7 (801) | 159.2 (283) |
| libgcc series + back end | 345.0 (838) | 216.0 (662) | 179.3 (609) | 159.2 (283) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1305.1 (3114) | 873.0 (2567) | 872.7 (2567) | 136.7 (259) |
| Upstream C + back end | 1305.1 (3114) | 873.0 (2567) | 872.7 (2567) | 136.7 (259) |
| Upstream C, no-divider code | 1302.7 (5360) | 314.2 (1179) | 276.2 (1128) | 276.2 (1128) |
| Upstream C, no-divider code + back end | 416.2 (1126) | 239.1 (854) | 199.1 (797) | 199.1 (797) |
| libgcc series | 440.2 (1220) | 257.2 (851) | 222.9 (800) | 136.7 (259) |
| libgcc series + back end | 351.9 (899) | 221.5 (722) | 187.2 (671) | 136.7 (259) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1302.6 (3071) | 900.5 (2583) | 900.3 (2583) | 156.1 (258) |
| Upstream C + back end | 1302.6 (3071) | 900.5 (2583) | 900.3 (2583) | 156.1 (258) |
| Upstream C, no-divider code | 1405.2 (5493) | 341.8 (1192) | 307.9 (1141) | 307.9 (1141) |
| Upstream C, no-divider code + back end | 502.3 (1341) | 259.1 (864) | 225.5 (813) | 225.5 (813) |
| libgcc series | 1311.6 (5302) | 337.4 (1187) | 306.5 (1141) | 156.1 (258) |
| libgcc series + back end | 413.2 (1132) | 259.5 (864) | 227.9 (818) | 156.1 (258) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1261.1 (3060) | 872.5 (2576) | 872.3 (2576) | 127.4 (232) |
| Upstream C + back end | 1261.1 (3060) | 872.5 (2576) | 872.3 (2576) | 127.4 (232) |
| Upstream C, no-divider code | 1376.0 (5568) | 325.8 (1193) | 292.3 (1143) | 292.3 (1143) |
| Upstream C, no-divider code + back end | 483.8 (1327) | 244.5 (861) | 210.9 (811) | 210.9 (811) |
| libgcc series | 1290.9 (5375) | 324.5 (1193) | 289.0 (1141) | 127.4 (232) |
| libgcc series + back end | 396.3 (1133) | 241.5 (860) | 212.6 (816) | 127.4 (232) |

## Estimated cycles, 3-stage (C_AREA_OPTIMIZED=1), little-endian

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 708.2 (870) | 708.2 (870) | 708.2 (870) | 708.2 (870) |
| Improved assembly, `moddi3-new.S` | 257.5 (903) | 257.5 (903) | 257.5 (903) | 257.5 (903) |
| Upstream C, `libgcc2.c` | 1846.5 (4222) | 1293.5 (3554) | 1293.1 (3554) | 202.2 (345) |
| Upstream C + back end | 1846.5 (4222) | 1293.5 (3554) | 1293.1 (3554) | 202.2 (345) |
| Upstream C, no-divider code | 1455.2 (5604) | 427.7 (1476) | 379.6 (1409) | 379.6 (1409) |
| Upstream C, no-divider code + back end | 563.5 (1437) | 336.0 (1091) | 281.7 (1013) | 281.7 (1013) |
| libgcc series | 548.4 (1368) | 348.3 (1015) | 294.3 (940) | 202.2 (345) |
| libgcc series + back end | 460.1 (1061) | 295.2 (830) | 242.0 (755) | 202.2 (345) |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1788.0 (4186) | 1259.1 (3530) | 1258.7 (3530) | 175.1 (320) |
| Upstream C + back end | 1788.0 (4186) | 1259.1 (3530) | 1258.7 (3530) | 175.1 (320) |
| Upstream C, no-divider code | 1419.3 (5667) | 400.6 (1470) | 346.3 (1403) | 346.3 (1403) |
| Upstream C, no-divider code + back end | 534.9 (1428) | 309.3 (1078) | 251.3 (998) | 251.3 (998) |
| libgcc series | 525.8 (1365) | 323.8 (1008) | 275.5 (937) | 175.1 (320) |
| libgcc series + back end | 462.9 (1107) | 296.0 (878) | 247.7 (807) | 175.1 (320) |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1783.1 (4147) | 1293.5 (3567) | 1293.3 (3567) | 196.7 (319) |
| Upstream C + back end | 1783.1 (4147) | 1293.5 (3567) | 1293.3 (3567) | 196.7 (319) |
| Upstream C, no-divider code | 1548.2 (5811) | 445.1 (1500) | 394.9 (1427) | 394.9 (1427) |
| Upstream C, no-divider code + back end | 646.3 (1771) | 336.7 (1095) | 287.9 (1023) | 287.9 (1023) |
| libgcc series | 1426.6 (5559) | 437.3 (1491) | 388.2 (1421) | 196.7 (319) |
| libgcc series + back end | 541.1 (1500) | 345.4 (1154) | 297.9 (1086) | 196.7 (319) |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1728.1 (4116) | 1257.7 (3544) | 1257.5 (3544) | 158.9 (282) |
| Upstream C + back end | 1728.1 (4116) | 1257.7 (3544) | 1257.5 (3544) | 158.9 (282) |
| Upstream C, no-divider code | 1515.9 (5943) | 418.8 (1494) | 372.6 (1427) | 372.6 (1427) |
| Upstream C, no-divider code + back end | 621.0 (1749) | 316.2 (1088) | 268.3 (1018) | 268.3 (1018) |
| libgcc series | 1399.8 (5628) | 417.0 (1493) | 366.9 (1422) | 158.9 (282) |
| libgcc series + back end | 517.3 (1499) | 319.3 (1146) | 280.6 (1087) | 158.9 (282) |

## Data-hazard stalls, 5-stage, little-endian

Mean cycles per call that UG984's data hazards add to either 5-stage figure, low and high bound.

### `__moddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Assembly fix, upstream `moddi3.S` | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 |
| Improved assembly, `moddi3-new.S` | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 | 0.0-0.0 |
| Upstream C, `libgcc2.c` | 1.0-1.1 | 3.5-3.7 | 3.5-3.7 | 6.9-7.8 |
| Upstream C + back end | 1.0-1.1 | 3.5-3.7 | 3.5-3.7 | 6.9-7.8 |
| Upstream C, no-divider code | 1.3-2.6 | 2.4-3.0 | 0.6-0.6 | 0.6-0.6 |
| Upstream C, no-divider code + back end | 1.3-2.6 | 2.4-3.0 | 0.6-0.6 | 0.6-0.6 |
| libgcc series | 1.3-2.6 | 2.1-2.7 | 0.3-0.3 | 6.9-7.8 |
| libgcc series + back end | 1.3-2.6 | 1.8-2.5 | 0.0-0.0 | 6.9-7.8 |

### `__umoddi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 1.0-1.2 | 2.7-3.0 | 2.7-3.0 | 6.2-6.8 |
| Upstream C + back end | 1.0-1.2 | 2.7-3.0 | 2.7-3.0 | 6.2-6.8 |
| Upstream C, no-divider code | 1.3-2.6 | 2.3-2.9 | 1.0-1.0 | 1.0-1.0 |
| Upstream C, no-divider code + back end | 2.0-3.7 | 2.7-3.3 | 1.0-1.0 | 1.0-1.0 |
| libgcc series | 1.3-2.6 | 2.0-2.6 | 0.3-0.3 | 6.2-6.8 |
| libgcc series + back end | 1.3-2.6 | 1.7-2.3 | 0.0-0.0 | 6.2-6.8 |

### `__divdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 2.3-3.9 | 4.5-5.3 | 4.5-5.3 | 6.2-6.9 |
| Upstream C + back end | 2.3-3.9 | 4.5-5.3 | 4.5-5.3 | 6.2-6.9 |
| Upstream C, no-divider code | 2.4-4.8 | 3.7-5.4 | 0.3-0.3 | 0.3-0.3 |
| Upstream C, no-divider code + back end | 1.3-2.6 | 2.1-2.7 | 0.3-0.3 | 0.3-0.3 |
| libgcc series | 2.0-4.0 | 3.0-4.3 | 0.5-0.5 | 6.2-6.9 |
| libgcc series + back end | 1.3-2.6 | 1.8-2.5 | 0.0-0.0 | 6.2-6.9 |

### `__udivdi3`

| version | no options | barrel shifter, hw multiply | everything but the divider | everything |
|---|---:|---:|---:|---:|
| Upstream C, `libgcc2.c` | 2.2-3.5 | 4.7-5.5 | 4.7-5.5 | 6.2-7.0 |
| Upstream C + back end | 2.2-3.5 | 4.7-5.5 | 4.7-5.5 | 6.2-7.0 |
| Upstream C, no-divider code | 1.3-2.6 | 2.4-3.0 | 0.7-0.7 | 0.7-0.7 |
| Upstream C, no-divider code + back end | 2.0-3.7 | 2.4-3.0 | 0.7-0.7 | 0.7-0.7 |
| libgcc series | 1.3-2.6 | 1.7-2.3 | 0.9-0.9 | 6.2-7.0 |
| libgcc series + back end | 1.7-3.4 | 2.1-2.7 | 0.4-0.4 | 6.2-7.0 |

