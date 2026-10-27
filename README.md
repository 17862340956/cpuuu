# r4：已通过单测的四分支组合

版本 `qilin-r4-20261028`。此包为完整源码/手机SH上传包，不是可直接刷入的KernelSU成品；没有预编译KO，没有开机自启脚本。

## 本轮范围

复用r3已在目标手机单独完成加载和读取的四分支：

1. UTS release：version/uname，1项字符串修改。
2. CPU root online/possible/present：3个回调。
3. topology core_id/physical_package_id/die_id：3个回调。
4. cpufreq available/boost frequency lists：2个回调。

组合总计8个指针+1项release=9。四个展示回调的函数内容与通过上机单项测试的r3逐字节一致，测试中固定其指纹。

CPUINFO仍暂缓，绝不写rodata、不改代码页、不做inline hook、不做bind mount、不改调度器真实cpumask；不生成CPU8-11目录。GPU/系统属性、nproc/affinity、related_cpus不参与本轮。

## 组合行为

- 默认stage=inspect，不修改任何展示项。
- stage=combo需要pointer_tests=1。先核对UTS写锁与范围，规划全部8个不同指针，检查名称、原回调和地址边界，然后才创建状态节点并发布。
- 发布前再次核对全部指针快照，UTS release最后写入。UTS写锁覆盖组合发布，避免release在本模块发布期间被并发更改。
- 多指针发布不是全局原子事务。预检失败在任何修改前返回错误；发布中若cmpxchg发现冲突，保留已生效项、跳过UTS、报告partial_conflict并保持模块代码常驻。即使第一个cmpxchg冲突，也因已持模块自引用而保留实例，重启清理。
- 不自动回滚、不运行时disable、不rmmod。它是有限测试版，不宣称长期稳定。
- 默认只读预检逐项报告preflight_uts/cpus/topology/cpufreq；任一非0时SH返回失败，不把“预检完成”等同于“预检通过”。

## 一次完整上传，避免缺文件

解压本包，把里面的内容放在GitHub仓库根目录，与原Makefile同级，覆盖旧版本；不要只上传ZIP，也不要套一层r4文件夹。

必须上传全部7个根目录文件：

```
cpuinfo_spoof.c
kirin9020.h
Makefile
fix_vermagic.py
verify_module.py
test_build_tools.py
cpu_test.sh
```

另外更新 `.github/workflows/build.yml`，保留该目录层级。README与校验记录可一起上传。

Actions选 **Build cpuinfo_spoof r4**。继续保留两个任务：

- build（DDK容器）：运行测试→编译→**Fix vermagic**。不要求容器提供pip。
- verify（标准Ubuntu+setup-python）：安装pyelftools 0.33，运行全部测试，核验实际KO版本/ELF/modinfo/DWARF回调，再上传最终产物。

只下载最终 `cpuinfo_spoof-r4`。`intermediate-unverified-do-not-load` 仍是未校验中间传递文件，不用于手机。

## 手机操作

1. 下载最终产物，先把KO与build_report.json发给助手做实际二进制核对。
2. 核对后，将产物里的cpuinfo_spoof.ko、build_report.json、cpu_test.sh三个文件一起放 `/data/adb/qilin_r4/`，不要混入r3文件。
3. 禁用其他旧自动加载项，重启清除r3驻留实例。
4. MT管理器对cpu_test.sh选择ROOT执行。第一次选1只读预检（或回车默认1）。非交互执行也默认inspect。把新日志包发来。
5. 预检通过后再重启，运行同一SH选6组合测试。不是运行旧脚本的all。

只读预检预期：

```
revision=qilin-r4-20261028
stage=inspect
state=inspect_only
applied=0
preflight_uts=0
preflight_cpus=0
preflight_topology=0
preflight_cpufreq=0
```

组合预期：

```
stage=combo
state=active
planned=9
applied=9
pointer_planned=8
pointer_applied=8
uts_applied=1
last_error=0
```

SH核对计数后，连续读三轮（轮间2秒）：uname/proc-version、三个CPU根文件、现存CPU0-7的24个拓扑ID值、CPU0的两个频率列表。全部吻合时共97个检查通过。每次读取前持久化last_step，遇到不一致停止下一轮。

组合加载后可再次运行SH选6，只读验证同一实例，不重新insmod。不需要重启就能补采稍后运行状态；切换stage或KO版本仍需重启。默认选1时若当前已是combo，脚本会提示项目不一致并停止，不会偷偷替换。

## 尚未完成的目标

- cpuinfo未伪装；真实8核和nproc维持原状。
- topology只测现存CPU0-7三个ID，siblings/mask和缺失CPU目录未实现，因此不等于完整12核拓扑。
- 频率列表仍是项目显示预设，不宣称真实Kirin9020频率；硬件运行频率不变。
- 系统/GPU属性仍单独处理，本轮不删除/更改驱动选择属性，也不填造GPU频率。
- 单测通过不证明组合长期稳定；r4需要新的编译与目标手机预检/组合实测。

## 本地验证边界

- 16项Python回归测试：含pyelftools环境16通过；不含依赖环境15通过、严格DWARF项按条件跳过。
- SH在实际Android shell做语法检查；另用隔离假接口副本测试预检成功、预检失败、组合结果匹配、组合结果不匹配、部分冲突五种路径。该测试不执行模块加载、不读取或改写真实CPU接口，不证明内核运行成功。
- 本机仍无可用内核构建环境；没有宣称r4已编译或上机加载。实际KO检查继续由Actions及下一次静态核对完成。
