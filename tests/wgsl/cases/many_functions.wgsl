// A long module (0.25.2): 240 functions, each called from the entry point:
// the translator's IR outgrows its arena's blocks
// (32 KiB), where a `let` copy of a function in std::gpu::wgsl once freed
// what the module still held (a crash or a wrong translation).
// JOB: dispatch 1 1 1
// JOB: buffer 0 0 16
// EXPECT: buffer 0 0
// EXPECT: 000000f0 00000000 00000000 00000000

@group(0) @binding(0) var<storage, read_write> xs: array<u32>;

fn f0(x: u32) -> u32 { return x + 1u; }
fn f1(x: u32) -> u32 { return x + 1u; }
fn f2(x: u32) -> u32 { return x + 1u; }
fn f3(x: u32) -> u32 { return x + 1u; }
fn f4(x: u32) -> u32 { return x + 1u; }
fn f5(x: u32) -> u32 { return x + 1u; }
fn f6(x: u32) -> u32 { return x + 1u; }
fn f7(x: u32) -> u32 { return x + 1u; }
fn f8(x: u32) -> u32 { return x + 1u; }
fn f9(x: u32) -> u32 { return x + 1u; }
fn f10(x: u32) -> u32 { return x + 1u; }
fn f11(x: u32) -> u32 { return x + 1u; }
fn f12(x: u32) -> u32 { return x + 1u; }
fn f13(x: u32) -> u32 { return x + 1u; }
fn f14(x: u32) -> u32 { return x + 1u; }
fn f15(x: u32) -> u32 { return x + 1u; }
fn f16(x: u32) -> u32 { return x + 1u; }
fn f17(x: u32) -> u32 { return x + 1u; }
fn f18(x: u32) -> u32 { return x + 1u; }
fn f19(x: u32) -> u32 { return x + 1u; }
fn f20(x: u32) -> u32 { return x + 1u; }
fn f21(x: u32) -> u32 { return x + 1u; }
fn f22(x: u32) -> u32 { return x + 1u; }
fn f23(x: u32) -> u32 { return x + 1u; }
fn f24(x: u32) -> u32 { return x + 1u; }
fn f25(x: u32) -> u32 { return x + 1u; }
fn f26(x: u32) -> u32 { return x + 1u; }
fn f27(x: u32) -> u32 { return x + 1u; }
fn f28(x: u32) -> u32 { return x + 1u; }
fn f29(x: u32) -> u32 { return x + 1u; }
fn f30(x: u32) -> u32 { return x + 1u; }
fn f31(x: u32) -> u32 { return x + 1u; }
fn f32(x: u32) -> u32 { return x + 1u; }
fn f33(x: u32) -> u32 { return x + 1u; }
fn f34(x: u32) -> u32 { return x + 1u; }
fn f35(x: u32) -> u32 { return x + 1u; }
fn f36(x: u32) -> u32 { return x + 1u; }
fn f37(x: u32) -> u32 { return x + 1u; }
fn f38(x: u32) -> u32 { return x + 1u; }
fn f39(x: u32) -> u32 { return x + 1u; }
fn f40(x: u32) -> u32 { return x + 1u; }
fn f41(x: u32) -> u32 { return x + 1u; }
fn f42(x: u32) -> u32 { return x + 1u; }
fn f43(x: u32) -> u32 { return x + 1u; }
fn f44(x: u32) -> u32 { return x + 1u; }
fn f45(x: u32) -> u32 { return x + 1u; }
fn f46(x: u32) -> u32 { return x + 1u; }
fn f47(x: u32) -> u32 { return x + 1u; }
fn f48(x: u32) -> u32 { return x + 1u; }
fn f49(x: u32) -> u32 { return x + 1u; }
fn f50(x: u32) -> u32 { return x + 1u; }
fn f51(x: u32) -> u32 { return x + 1u; }
fn f52(x: u32) -> u32 { return x + 1u; }
fn f53(x: u32) -> u32 { return x + 1u; }
fn f54(x: u32) -> u32 { return x + 1u; }
fn f55(x: u32) -> u32 { return x + 1u; }
fn f56(x: u32) -> u32 { return x + 1u; }
fn f57(x: u32) -> u32 { return x + 1u; }
fn f58(x: u32) -> u32 { return x + 1u; }
fn f59(x: u32) -> u32 { return x + 1u; }
fn f60(x: u32) -> u32 { return x + 1u; }
fn f61(x: u32) -> u32 { return x + 1u; }
fn f62(x: u32) -> u32 { return x + 1u; }
fn f63(x: u32) -> u32 { return x + 1u; }
fn f64(x: u32) -> u32 { return x + 1u; }
fn f65(x: u32) -> u32 { return x + 1u; }
fn f66(x: u32) -> u32 { return x + 1u; }
fn f67(x: u32) -> u32 { return x + 1u; }
fn f68(x: u32) -> u32 { return x + 1u; }
fn f69(x: u32) -> u32 { return x + 1u; }
fn f70(x: u32) -> u32 { return x + 1u; }
fn f71(x: u32) -> u32 { return x + 1u; }
fn f72(x: u32) -> u32 { return x + 1u; }
fn f73(x: u32) -> u32 { return x + 1u; }
fn f74(x: u32) -> u32 { return x + 1u; }
fn f75(x: u32) -> u32 { return x + 1u; }
fn f76(x: u32) -> u32 { return x + 1u; }
fn f77(x: u32) -> u32 { return x + 1u; }
fn f78(x: u32) -> u32 { return x + 1u; }
fn f79(x: u32) -> u32 { return x + 1u; }
fn f80(x: u32) -> u32 { return x + 1u; }
fn f81(x: u32) -> u32 { return x + 1u; }
fn f82(x: u32) -> u32 { return x + 1u; }
fn f83(x: u32) -> u32 { return x + 1u; }
fn f84(x: u32) -> u32 { return x + 1u; }
fn f85(x: u32) -> u32 { return x + 1u; }
fn f86(x: u32) -> u32 { return x + 1u; }
fn f87(x: u32) -> u32 { return x + 1u; }
fn f88(x: u32) -> u32 { return x + 1u; }
fn f89(x: u32) -> u32 { return x + 1u; }
fn f90(x: u32) -> u32 { return x + 1u; }
fn f91(x: u32) -> u32 { return x + 1u; }
fn f92(x: u32) -> u32 { return x + 1u; }
fn f93(x: u32) -> u32 { return x + 1u; }
fn f94(x: u32) -> u32 { return x + 1u; }
fn f95(x: u32) -> u32 { return x + 1u; }
fn f96(x: u32) -> u32 { return x + 1u; }
fn f97(x: u32) -> u32 { return x + 1u; }
fn f98(x: u32) -> u32 { return x + 1u; }
fn f99(x: u32) -> u32 { return x + 1u; }
fn f100(x: u32) -> u32 { return x + 1u; }
fn f101(x: u32) -> u32 { return x + 1u; }
fn f102(x: u32) -> u32 { return x + 1u; }
fn f103(x: u32) -> u32 { return x + 1u; }
fn f104(x: u32) -> u32 { return x + 1u; }
fn f105(x: u32) -> u32 { return x + 1u; }
fn f106(x: u32) -> u32 { return x + 1u; }
fn f107(x: u32) -> u32 { return x + 1u; }
fn f108(x: u32) -> u32 { return x + 1u; }
fn f109(x: u32) -> u32 { return x + 1u; }
fn f110(x: u32) -> u32 { return x + 1u; }
fn f111(x: u32) -> u32 { return x + 1u; }
fn f112(x: u32) -> u32 { return x + 1u; }
fn f113(x: u32) -> u32 { return x + 1u; }
fn f114(x: u32) -> u32 { return x + 1u; }
fn f115(x: u32) -> u32 { return x + 1u; }
fn f116(x: u32) -> u32 { return x + 1u; }
fn f117(x: u32) -> u32 { return x + 1u; }
fn f118(x: u32) -> u32 { return x + 1u; }
fn f119(x: u32) -> u32 { return x + 1u; }
fn f120(x: u32) -> u32 { return x + 1u; }
fn f121(x: u32) -> u32 { return x + 1u; }
fn f122(x: u32) -> u32 { return x + 1u; }
fn f123(x: u32) -> u32 { return x + 1u; }
fn f124(x: u32) -> u32 { return x + 1u; }
fn f125(x: u32) -> u32 { return x + 1u; }
fn f126(x: u32) -> u32 { return x + 1u; }
fn f127(x: u32) -> u32 { return x + 1u; }
fn f128(x: u32) -> u32 { return x + 1u; }
fn f129(x: u32) -> u32 { return x + 1u; }
fn f130(x: u32) -> u32 { return x + 1u; }
fn f131(x: u32) -> u32 { return x + 1u; }
fn f132(x: u32) -> u32 { return x + 1u; }
fn f133(x: u32) -> u32 { return x + 1u; }
fn f134(x: u32) -> u32 { return x + 1u; }
fn f135(x: u32) -> u32 { return x + 1u; }
fn f136(x: u32) -> u32 { return x + 1u; }
fn f137(x: u32) -> u32 { return x + 1u; }
fn f138(x: u32) -> u32 { return x + 1u; }
fn f139(x: u32) -> u32 { return x + 1u; }
fn f140(x: u32) -> u32 { return x + 1u; }
fn f141(x: u32) -> u32 { return x + 1u; }
fn f142(x: u32) -> u32 { return x + 1u; }
fn f143(x: u32) -> u32 { return x + 1u; }
fn f144(x: u32) -> u32 { return x + 1u; }
fn f145(x: u32) -> u32 { return x + 1u; }
fn f146(x: u32) -> u32 { return x + 1u; }
fn f147(x: u32) -> u32 { return x + 1u; }
fn f148(x: u32) -> u32 { return x + 1u; }
fn f149(x: u32) -> u32 { return x + 1u; }
fn f150(x: u32) -> u32 { return x + 1u; }
fn f151(x: u32) -> u32 { return x + 1u; }
fn f152(x: u32) -> u32 { return x + 1u; }
fn f153(x: u32) -> u32 { return x + 1u; }
fn f154(x: u32) -> u32 { return x + 1u; }
fn f155(x: u32) -> u32 { return x + 1u; }
fn f156(x: u32) -> u32 { return x + 1u; }
fn f157(x: u32) -> u32 { return x + 1u; }
fn f158(x: u32) -> u32 { return x + 1u; }
fn f159(x: u32) -> u32 { return x + 1u; }
fn f160(x: u32) -> u32 { return x + 1u; }
fn f161(x: u32) -> u32 { return x + 1u; }
fn f162(x: u32) -> u32 { return x + 1u; }
fn f163(x: u32) -> u32 { return x + 1u; }
fn f164(x: u32) -> u32 { return x + 1u; }
fn f165(x: u32) -> u32 { return x + 1u; }
fn f166(x: u32) -> u32 { return x + 1u; }
fn f167(x: u32) -> u32 { return x + 1u; }
fn f168(x: u32) -> u32 { return x + 1u; }
fn f169(x: u32) -> u32 { return x + 1u; }
fn f170(x: u32) -> u32 { return x + 1u; }
fn f171(x: u32) -> u32 { return x + 1u; }
fn f172(x: u32) -> u32 { return x + 1u; }
fn f173(x: u32) -> u32 { return x + 1u; }
fn f174(x: u32) -> u32 { return x + 1u; }
fn f175(x: u32) -> u32 { return x + 1u; }
fn f176(x: u32) -> u32 { return x + 1u; }
fn f177(x: u32) -> u32 { return x + 1u; }
fn f178(x: u32) -> u32 { return x + 1u; }
fn f179(x: u32) -> u32 { return x + 1u; }
fn f180(x: u32) -> u32 { return x + 1u; }
fn f181(x: u32) -> u32 { return x + 1u; }
fn f182(x: u32) -> u32 { return x + 1u; }
fn f183(x: u32) -> u32 { return x + 1u; }
fn f184(x: u32) -> u32 { return x + 1u; }
fn f185(x: u32) -> u32 { return x + 1u; }
fn f186(x: u32) -> u32 { return x + 1u; }
fn f187(x: u32) -> u32 { return x + 1u; }
fn f188(x: u32) -> u32 { return x + 1u; }
fn f189(x: u32) -> u32 { return x + 1u; }
fn f190(x: u32) -> u32 { return x + 1u; }
fn f191(x: u32) -> u32 { return x + 1u; }
fn f192(x: u32) -> u32 { return x + 1u; }
fn f193(x: u32) -> u32 { return x + 1u; }
fn f194(x: u32) -> u32 { return x + 1u; }
fn f195(x: u32) -> u32 { return x + 1u; }
fn f196(x: u32) -> u32 { return x + 1u; }
fn f197(x: u32) -> u32 { return x + 1u; }
fn f198(x: u32) -> u32 { return x + 1u; }
fn f199(x: u32) -> u32 { return x + 1u; }
fn f200(x: u32) -> u32 { return x + 1u; }
fn f201(x: u32) -> u32 { return x + 1u; }
fn f202(x: u32) -> u32 { return x + 1u; }
fn f203(x: u32) -> u32 { return x + 1u; }
fn f204(x: u32) -> u32 { return x + 1u; }
fn f205(x: u32) -> u32 { return x + 1u; }
fn f206(x: u32) -> u32 { return x + 1u; }
fn f207(x: u32) -> u32 { return x + 1u; }
fn f208(x: u32) -> u32 { return x + 1u; }
fn f209(x: u32) -> u32 { return x + 1u; }
fn f210(x: u32) -> u32 { return x + 1u; }
fn f211(x: u32) -> u32 { return x + 1u; }
fn f212(x: u32) -> u32 { return x + 1u; }
fn f213(x: u32) -> u32 { return x + 1u; }
fn f214(x: u32) -> u32 { return x + 1u; }
fn f215(x: u32) -> u32 { return x + 1u; }
fn f216(x: u32) -> u32 { return x + 1u; }
fn f217(x: u32) -> u32 { return x + 1u; }
fn f218(x: u32) -> u32 { return x + 1u; }
fn f219(x: u32) -> u32 { return x + 1u; }
fn f220(x: u32) -> u32 { return x + 1u; }
fn f221(x: u32) -> u32 { return x + 1u; }
fn f222(x: u32) -> u32 { return x + 1u; }
fn f223(x: u32) -> u32 { return x + 1u; }
fn f224(x: u32) -> u32 { return x + 1u; }
fn f225(x: u32) -> u32 { return x + 1u; }
fn f226(x: u32) -> u32 { return x + 1u; }
fn f227(x: u32) -> u32 { return x + 1u; }
fn f228(x: u32) -> u32 { return x + 1u; }
fn f229(x: u32) -> u32 { return x + 1u; }
fn f230(x: u32) -> u32 { return x + 1u; }
fn f231(x: u32) -> u32 { return x + 1u; }
fn f232(x: u32) -> u32 { return x + 1u; }
fn f233(x: u32) -> u32 { return x + 1u; }
fn f234(x: u32) -> u32 { return x + 1u; }
fn f235(x: u32) -> u32 { return x + 1u; }
fn f236(x: u32) -> u32 { return x + 1u; }
fn f237(x: u32) -> u32 { return x + 1u; }
fn f238(x: u32) -> u32 { return x + 1u; }
fn f239(x: u32) -> u32 { return x + 1u; }

@compute @workgroup_size(1) fn main() {
    var acc = 0u;
    acc = f0(acc);
    acc = f1(acc);
    acc = f2(acc);
    acc = f3(acc);
    acc = f4(acc);
    acc = f5(acc);
    acc = f6(acc);
    acc = f7(acc);
    acc = f8(acc);
    acc = f9(acc);
    acc = f10(acc);
    acc = f11(acc);
    acc = f12(acc);
    acc = f13(acc);
    acc = f14(acc);
    acc = f15(acc);
    acc = f16(acc);
    acc = f17(acc);
    acc = f18(acc);
    acc = f19(acc);
    acc = f20(acc);
    acc = f21(acc);
    acc = f22(acc);
    acc = f23(acc);
    acc = f24(acc);
    acc = f25(acc);
    acc = f26(acc);
    acc = f27(acc);
    acc = f28(acc);
    acc = f29(acc);
    acc = f30(acc);
    acc = f31(acc);
    acc = f32(acc);
    acc = f33(acc);
    acc = f34(acc);
    acc = f35(acc);
    acc = f36(acc);
    acc = f37(acc);
    acc = f38(acc);
    acc = f39(acc);
    acc = f40(acc);
    acc = f41(acc);
    acc = f42(acc);
    acc = f43(acc);
    acc = f44(acc);
    acc = f45(acc);
    acc = f46(acc);
    acc = f47(acc);
    acc = f48(acc);
    acc = f49(acc);
    acc = f50(acc);
    acc = f51(acc);
    acc = f52(acc);
    acc = f53(acc);
    acc = f54(acc);
    acc = f55(acc);
    acc = f56(acc);
    acc = f57(acc);
    acc = f58(acc);
    acc = f59(acc);
    acc = f60(acc);
    acc = f61(acc);
    acc = f62(acc);
    acc = f63(acc);
    acc = f64(acc);
    acc = f65(acc);
    acc = f66(acc);
    acc = f67(acc);
    acc = f68(acc);
    acc = f69(acc);
    acc = f70(acc);
    acc = f71(acc);
    acc = f72(acc);
    acc = f73(acc);
    acc = f74(acc);
    acc = f75(acc);
    acc = f76(acc);
    acc = f77(acc);
    acc = f78(acc);
    acc = f79(acc);
    acc = f80(acc);
    acc = f81(acc);
    acc = f82(acc);
    acc = f83(acc);
    acc = f84(acc);
    acc = f85(acc);
    acc = f86(acc);
    acc = f87(acc);
    acc = f88(acc);
    acc = f89(acc);
    acc = f90(acc);
    acc = f91(acc);
    acc = f92(acc);
    acc = f93(acc);
    acc = f94(acc);
    acc = f95(acc);
    acc = f96(acc);
    acc = f97(acc);
    acc = f98(acc);
    acc = f99(acc);
    acc = f100(acc);
    acc = f101(acc);
    acc = f102(acc);
    acc = f103(acc);
    acc = f104(acc);
    acc = f105(acc);
    acc = f106(acc);
    acc = f107(acc);
    acc = f108(acc);
    acc = f109(acc);
    acc = f110(acc);
    acc = f111(acc);
    acc = f112(acc);
    acc = f113(acc);
    acc = f114(acc);
    acc = f115(acc);
    acc = f116(acc);
    acc = f117(acc);
    acc = f118(acc);
    acc = f119(acc);
    acc = f120(acc);
    acc = f121(acc);
    acc = f122(acc);
    acc = f123(acc);
    acc = f124(acc);
    acc = f125(acc);
    acc = f126(acc);
    acc = f127(acc);
    acc = f128(acc);
    acc = f129(acc);
    acc = f130(acc);
    acc = f131(acc);
    acc = f132(acc);
    acc = f133(acc);
    acc = f134(acc);
    acc = f135(acc);
    acc = f136(acc);
    acc = f137(acc);
    acc = f138(acc);
    acc = f139(acc);
    acc = f140(acc);
    acc = f141(acc);
    acc = f142(acc);
    acc = f143(acc);
    acc = f144(acc);
    acc = f145(acc);
    acc = f146(acc);
    acc = f147(acc);
    acc = f148(acc);
    acc = f149(acc);
    acc = f150(acc);
    acc = f151(acc);
    acc = f152(acc);
    acc = f153(acc);
    acc = f154(acc);
    acc = f155(acc);
    acc = f156(acc);
    acc = f157(acc);
    acc = f158(acc);
    acc = f159(acc);
    acc = f160(acc);
    acc = f161(acc);
    acc = f162(acc);
    acc = f163(acc);
    acc = f164(acc);
    acc = f165(acc);
    acc = f166(acc);
    acc = f167(acc);
    acc = f168(acc);
    acc = f169(acc);
    acc = f170(acc);
    acc = f171(acc);
    acc = f172(acc);
    acc = f173(acc);
    acc = f174(acc);
    acc = f175(acc);
    acc = f176(acc);
    acc = f177(acc);
    acc = f178(acc);
    acc = f179(acc);
    acc = f180(acc);
    acc = f181(acc);
    acc = f182(acc);
    acc = f183(acc);
    acc = f184(acc);
    acc = f185(acc);
    acc = f186(acc);
    acc = f187(acc);
    acc = f188(acc);
    acc = f189(acc);
    acc = f190(acc);
    acc = f191(acc);
    acc = f192(acc);
    acc = f193(acc);
    acc = f194(acc);
    acc = f195(acc);
    acc = f196(acc);
    acc = f197(acc);
    acc = f198(acc);
    acc = f199(acc);
    acc = f200(acc);
    acc = f201(acc);
    acc = f202(acc);
    acc = f203(acc);
    acc = f204(acc);
    acc = f205(acc);
    acc = f206(acc);
    acc = f207(acc);
    acc = f208(acc);
    acc = f209(acc);
    acc = f210(acc);
    acc = f211(acc);
    acc = f212(acc);
    acc = f213(acc);
    acc = f214(acc);
    acc = f215(acc);
    acc = f216(acc);
    acc = f217(acc);
    acc = f218(acc);
    acc = f219(acc);
    acc = f220(acc);
    acc = f221(acc);
    acc = f222(acc);
    acc = f223(acc);
    acc = f224(acc);
    acc = f225(acc);
    acc = f226(acc);
    acc = f227(acc);
    acc = f228(acc);
    acc = f229(acc);
    acc = f230(acc);
    acc = f231(acc);
    acc = f232(acc);
    acc = f233(acc);
    acc = f234(acc);
    acc = f235(acc);
    acc = f236(acc);
    acc = f237(acc);
    acc = f238(acc);
    acc = f239(acc);
    xs[0] = acc;
}
