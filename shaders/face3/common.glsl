/*
================================================================================
主要渲染逻辑
Main rendering logic
================================================================================
*/



// --------------------------------------------------------------------------------

/* 物理参数 / Physical parameters */

// 时空参数 / Spacetime Settings
#define MAX_EXTENSION           0       // 最大延拓开关 / Maximal Extension Toggle
#define iWhitehole              MAX_EXTENSION // 白洞 (随最大延拓开启) / White Hole (Linked to Maximal Extension)
#define iBlackHoleMassSol       1.0e7   // 黑洞质量 (太阳质量倍数,可为负) / Black Hole Mass (Solar Masses,can be negative)
#define iSpin                   0.997114514 // 无量纲自旋 a* (可为任意实数) / Dimensionless Spin a* (can be any real number)
#define iQ2                     0.0     // 电荷平方，可为负数 / Dimensionless Charge Squared Q*^2, Can be negative
#define WORLD_TIME_UNITS_PER_SECOND 2.0 // 每秒对应物理演化时间 (Rs/c) / Rs/c Time Units per Second

// 辅助图表 / Diagnostics & Diagrams
#define iShowTopologyMap        1       // 截面拓扑图 / Topology Cross-Section Map
#define iShowPenroseMap         1       // 彭罗斯图 / Carter-Penrose Diagram

// 渲染参数 / Rendering Settings
#define iFovRadians             (60.0 * 0.01745329252) // 视野 (弧度) / Field of View (Radians)
#define iAdaptiveStepFeedback   0       // 自适应步进误差反馈 / Adaptive Step Error Feedback
#define iFeedbackTolerance      1e-4    // 近场嵌入误差容差，随质量四次方收紧 / Near-field embedded tolerance, scaled by quality^4
#define iFeedbackStepScale      1.5     // 平缓光路的几何步长倍率 / Geometric step multiplier for smooth rays
#define iEnableShadowCulling    1       // 开启阴影剔除优化 / Enable Shadow Culling Optimization
#define SHADOW_CULLING_PUSH_RATIO 0.8   // 视界至物质内缘间隙的剔除比例，0~1 / Culling fraction of the horizon-to-matter gap
#define iQuality                1.0     // 步长精细度 / Raymarching Step Quality Factor

// 降采样与局部重算 / Downsampling and Local Retracing
#define RAY_DOWNSAMPLE          2       // 降采样倍数；1=关闭，2=0.5分辨率，4=0.25分辨率 / divisor; 1=off
#define RAY_MIN_PIXELS         518401   // 像素低于此值时不降采样 / Full-resolution fallback below this pixel count
#define RAY_EDGE_COS            0.8     // 逸出方向夹角阈值 / Escape-direction cosine threshold
#define RAY_PREPASS_STEPS       64      // 预计算步数预算；0=不限，超出后完整重算 / Prepass step budget; 0=unlimited, retrace unfinished rays
#define RAY_VOLUME_INTERPOLATION 3      // 盘/体积插值：0=最近邻 Nearest，1=双线性 Bilinear，2=限幅 Catmull-Rom，3=B 样条 / Volume filter
#define RAY_SKY_INTERPOLATION    3      // 出射方向/频移插值：规则同上 / Escape direction and shift filter, same rules as above

#define iPointSourceBrightening 1       // 强透镜点光源立体角增亮 / Point Source Solid Angle Brightening
#define iEnableHeatHaze         1       // 开启热浪折射 / Enable Heat Haze Refraction
#define iPolarization           0       // 偏振模式 (0:关 1:伪彩色 2:模拟偏振片) / Polarization Mode (0:Off 1:False-Color 2:Polarizer)
#define iGrid                   0       // 坐标网格 (0:关 1:黑体 2:固定色) / Coordinate Grid (0:Off 1:Blackbody 2:Fixed Color)

#define iMu                     1.0     // 吸积物质比荷 / Specific Charge of Accreting Matter
#define iAccretionRate          5.0e-4  // 吸积率 (爱丁顿吸积率倍数) / Accretion Rate (Eddington Units)

#define iInterRadiusRs          2.0     // 吸积盘内半径 (Rs) / Accretion Disk Inner Radius (Rs)
#define iOuterRadiusRs          20.0    // 吸积盘外半径 (Rs) / Accretion Disk Outer Radius (Rs)
#define iThinRs                 0.75    // 吸积盘基准半厚度 (Rs) / Accretion Disk Base Half-Thickness (Rs)
#define iInnerCloudFadeRs       0.5     // 内侧云的淡入宽度(Rs) / Inner cloud fade width(Rs) from the inner edge
#define iHopper                 0.24    // 吸积盘厚度径向斜率 / Accretion Disk Thickness Slope
#define iBrightmut              1.0     // 吸积盘亮度乘数 / Accretion Disk Brightness Multiplier
#define iDarkmut                0.5     // 吸积盘不透明度 / Accretion Disk Opacity
#define iReddening              0.3     // 盘消光红化因子 / Disk Reddening Factor
#define iSaturation             0.5     // 吸积盘饱和度 / Accretion Disk Saturation
#define iBlackbodyIntensityExponent 0.5 // 黑体强度指数 / Blackbody Intensity Exponent
#define iRedShiftColorExponent  3.0     // 频移色温指数 / Redshift Color Temp Exponent
#define iRedShiftIntensityExponent 4.0  // 频移亮度指数 / Redshift Intensity Exponent

#define iJetRedShiftIntensityExponent 2.0 // 喷流频移亮度指数 / Jet Redshift Intensity Exponent
#define iJetBrightmut           1.0     // 喷流亮度乘数 / Jet Brightness Multiplier
#define iJetSaturation          0.0     // 喷流饱和度 / Jet Saturation
#define iJetShiftMax            3.0     // 喷流最大蓝移限制 / Jet Max Blue Shift

#define iDensestarsurfaceR      0.0     // 致密星表面半径 (0:隐藏) / Compact Star Surface Radius (0:Hides)
#define iDensestarBlackbodyIntensityExponent 4.0 // 致密星黑体强度指数 / Compact Star Blackbody Intensity Exponent
#define iDensestarRedShiftColorExponent      1.0 // 致密星频移色温指数 / Compact Star Redshift Color Temp Exponent
#define iDensestarRedShiftIntensityExponent  4.0 // 致密星频移亮度指数 / Compact Star Redshift Intensity Exponent
#define iDensestarBrightmut     1.0     // 致密星表面亮度乘数 / Compact Star Surface Brightness Multiplier

#define BG_SHIFT_MODE           2       // 背景星空频移：1=三色光谱，2=黑体曲线 / Background sky shift: 1=three-color spectrum, 2=blackbody locus
#define iBackgroundBrightmut    1.0     // 背景星空亮度乘数 / Background Brightness Multiplier
#define iBackShiftMax           5.0     // 背景最大蓝移限制 / Max Background Frequency Shift
#define BG_SHIFT_WHITEN         1       // 强蓝移时的RGB保底开关 / Floor dark channels in bright blueshifted sources
#define BG_WHITEN_SHIFT         vec2(3.2, 5.0) // 保底频移过渡范围 / Channel-floor frequency-shift interval
#define BG_WHITEN_BRIGHTNESS    vec2(3.2, 5.0) // 保底输入亮度过渡 / Channel-floor input peak-brightness interval
#define BG_WHITEN_FLOOR         0.10    // 完整强度时的通道下限，相对于峰值 / Channel floor relative to peak at full strength

#define ANTIVERSE_RAIN_3D       0       // 反宇宙数字雨：0=无穷远背景，1=3D可穿越 / Rain: 0=infinite background, 1=3D traversable
#define ANTIVERSE_SHIFT_MODE    1       // 数字雨频移：1=三色光谱，2=黑体曲线 / Digital rain shift: 1=three-color spectrum, 2=blackbody locus
#define RAIN_SCALE_RS           6.0     // 数字雨尺寸大小 / Rain spatial scale
#define RAIN_DISTANCE_RS        (60.0*RAIN_SCALE_RS) // 数字雨远处淡出距离 / Visible path length
#define RAIN_SPEED              1.0     // 字符图案滚动速度 / Pattern speed multiplier

#define iPhotonRingBoost        7.0     // 光子环亮度增亮 / Photon Ring Brightness Boost
#define iPhotonRingColorTempBoost 2.0   // 光子环色温增益 (蓝移) / Photon Ring Color Temp Boost (Blue Shift)
#define iBoostRot               0.75    // 自旋导致的亮度非对称程度 / Brightness Asymmetry Boost for Spin

#define iPolarizationAngle      0.0     // 偏振片角度 / Polarization Filter Angle
#define iHeatHaze               1.0     // 热浪扰动强度 / Heat Haze Disturbance Strength

#define iUseImageDisk           0       // 开启贴图吸积盘 (A/D iChannel0) / Enable Texture Disk (A/D iChannel0)
#define iImageRotationSpeed     0.008   // 贴图旋转速度 / Texture Disk Rotation Speed

#define iBlendWeight            0.5     // TAA 混合权重 / TAA Blend Weight

#define iDEBUG                  0       // 调试模式 (0:正常 其它见TraceRay) / Debug Mode (0:Normal, see TraceRay for others)
#define SHADOW_CULL_DEBUG       0       // 剔除诊断：0=关，1=显示已剔除的，2=按捕获情况分类 / Culling diagnostic: 0=off, 1=terminated, 2=classification

// --------------------------------------------------------------------------------

/* 相机参数 / Camera parameters */

// 观者控制模式 / Observer & Controls
#define CAMERA_MODE             2       // 观者模式 (0:静态 1:落体 2:局部目标速度 4:类时世界线) / Observer Mode (0:Static 1:Free Fall 2:Target Velocity 4:Timelike Worldline)
#define CAMERA_CONTROL_MODE     0       // 控制模式 (0:自由视角 1:环绕并注视黑洞) / Control Mode (0:Free 1:Orbit Center-locked)
/* 注：
CAMERA_CONTROL_MODE为1且CAMERA_MODE不为4时，鼠标拖动改变角度，W/S调整远近。
CAMERA_MODE为4时，按WASD/RF给相机产生本征加速度，+和-调整加速度大小。
When CAMERA_CONTROL_MODE is 1 and CAMERA_MODE is not 4, dragging mouse changes the angle, W/S adjust the distance.
When CAMERA_MODE is 4, WASD/RF applies proper acceleration, with + and - adjusting its strength.
*/

// 相机初始姿态 (单位: Rs) / Initial Camera Transform (Units: Rs)
#define CAMERA_INIT_POSITION    vec3(-2.0, -3.6, 22.0) // 初始位置 / Initial Camera Position
#define CAMERA_INIT_DIRECTION   vec3(0.03, 0.16, -1.0) // 初始视线方向 / Initial Camera Look Direction
#define CAMERA_INIT_UP          vec3(-0.5, 1.0, 0.0)   // 初始上方向 / Initial Camera Up Direction

// 控制平滑化 / Controls Smoothing
#define CAMERA_MOVE_RESPONSE    0.18    // 位移响应时间 (秒，0为立即响应) / Movement Response Time (s, 0:Instant)
#define CAMERA_TURN_RESPONSE    0.12    // 转向响应时间 (秒，0为立即响应) / Turning Response Time (s, 0:Instant)

// 类时世界线模式参数 (CAMERA_MODE = 4) / Timelike Worldline Dynamics
#define CAMERA_THRUST           1.5     // 本征加速度推力 / Proper Acceleration Thrust
#define CAMERA_TIME_RATE        1.0     // 世界线额外时间流逝倍率 / Additional Time Rate Multiplier
#define CAMERA_INIT_VELOCITY    vec3(0.0) // 初始坐标速度 / Initial Coordinate Velocity
#define CAMERA_SPECIFIC_CHARGE  0.0     // 相机比荷 (q/m) / Camera Specific Charge
#define CAMERA_ELECTRIC_CHARGE  0.0     // 相机电荷 / Camera Electric Charge
#define CAMERA_MAGNETIC_CHARGE  0.0     // 相机磁荷 / Camera Magnetic Charge

// --------------------------------------------------------------------------------



#if RAY_DOWNSAMPLE < 1
    #error RAY_DOWNSAMPLE must be a positive integer
#endif
#if RAY_VOLUME_INTERPOLATION < 0 || RAY_VOLUME_INTERPOLATION > 3 || RAY_SKY_INTERPOLATION < 0 || RAY_SKY_INTERPOLATION > 3
    #error Interpolation must be 0, 1, 2 or 3
#endif

#if CAMERA_MODE != 0 && CAMERA_MODE != 1 && CAMERA_MODE != 2 && CAMERA_MODE != 4
    #error CAMERA_MODE must be 0, 1, 2 or 4
#endif

// 键位码 / Keyboard codes
const int KEY_W = 87;
const int KEY_A = 65;
const int KEY_S = 83;
const int KEY_D = 68;
const int KEY_Q = 81;
const int KEY_E = 69;
const int KEY_R = 82;
const int KEY_F = 70;
const int KEY_G = 71;
const int KEY_PLUS = 187;
const int KEY_MINUS = 189;
const int KEY_NUMPAD_PLUS = 107;
const int KEY_NUMPAD_MINUS = 109;
const int KEY_TIME_SLOWER = 219;
const int KEY_TIME_FASTER = 221;

// 移动与鼠标的基本速度 / Base movement and mouse speeds
const float MOVE_SPEED = 2.5; 
const float MOUSE_SENSITIVITY = 0.003;
const float ROLL_SPEED = 2.0;
const float ORBIT_ZOOM_SPEED = 0.15;

// 纹理、相机采样器与画布尺寸由调用通道提供。
vec3 rayResolution;
float iTraceTime;

mat4 iInverseCamRot;
vec4 iBlackHoleRelativePosRs;
vec4 iBlackHoleRelativeDiskNormal;
vec4 iBlackHoleRelativeDiskTangen;
vec4 iCameraVelocity;
vec4 ie1_up, ie2_up, ie3_up, iU_up;
int iCamDataCoordisOutgoing;
int iInWhichUniverse;
// 观者模式由 Common 统一配置，可在编译时裁去其它模式的分支。
const int iObserverMode = CAMERA_MODE == 4 ? -1 : CAMERA_MODE;
float iUniverseSign;
float iBlackHoleTime;
float iGameTime;
float iTimeRate;

// GLSL ES 3.00 缺少 fma。这里保留显式乘加，确保浏览器可以编译。
#define fma(a,b,c) ((a)*(b)+(c))

#ifndef COORDCONVERTER_GLSL_
#define COORDCONVERTER_GLSL_

vec3 FragUvToDir(vec2 FragUv, float Fov, vec2 NdcResolution)
{
    return normalize(vec3(Fov * (2.0 * FragUv.x - 1.0),
                          Fov * (2.0 * FragUv.y - 1.0) * NdcResolution.y / NdcResolution.x,
                          -1.0));
}

vec2 PosToNdc(vec4 Pos, vec2 NdcResolution)
{
    return vec2(-Pos.x / Pos.z, -Pos.y / Pos.z * NdcResolution.x / NdcResolution.y);
}

vec2 DirToNdc(vec3 Dir, vec2 NdcResolution)
{
    return vec2(-Dir.x / Dir.z, -Dir.y / Dir.z * NdcResolution.x / NdcResolution.y);
}

vec2 DirToFragUv(vec3 Dir, vec2 NdcResolution)
{
    return vec2(0.5 - 0.5 * Dir.x / Dir.z, 0.5 - 0.5 * Dir.y / Dir.z * NdcResolution.x / NdcResolution.y);
}

vec2 PosToFragUv(vec4 Pos, vec2 NdcResolution)
{
    return vec2(0.5 - 0.5 * Pos.x / Pos.z, 0.5 - 0.5 * Pos.y / Pos.z * NdcResolution.x / NdcResolution.y);
}

#endif // !COORDCONVERTER_GLSL_

#ifndef NUMERICCONSTANTS_GLSL_
#define NUMERICCONSTANTS_GLSL_

const float kPi          = 3.1415926535897932384626433832795;
const float k2Pi         = 6.283185307179586476925286766559;
const float kEuler       = 2.7182818284590452353602874713527;
const float kRadToDegree = 57.295779513082320876798154814105;
const float kDegreeToRad = 0.017453292519943295769236907684886;

const float kGravityConstant = 6.6743e-11;
const float kSpeedOfLight    = 299792458.0;
const float kSolarMass       = 1.9884e30;

#endif // !NUMERICCONSTANTS_GLSL_

// =============================================================================
vec4 hash43x(vec3 p) {
    uvec3 x = uvec3(ivec3(p));
    x = 1103515245U*((x.xyz >> 1U)^(x.yzx));
    uint h = 1103515245U*((x.x^x.z)^(x.y>>3U));
    uvec4 rz = uvec4(h, h*16807U, h*48271U, h*69621U);
    return vec4((rz >> 1) & uvec4(0x7fffffffU))/float(0x7fffffff);
}
vec3 stars(vec3 p) {
    vec3 col = vec3(0); float rad = .087*rayResolution.y; float dens = 0.15; float id = 0.; float z = 1.;
    for (float i = 0.; i < 5.; i++) {
        p *= mat3(0.86564, -0.28535, 0.41140, 0.50033, 0.46255, -0.73193, 0.01856, 0.83942, 0.54317);
        vec3 q = abs(p); vec3 p2 = p/max(q.x, max(q.y,q.z)); p2 *= rad;
        vec3 ip = floor(p2 + 1e-5); vec3 fp = fract(p2 + 1e-5);
        vec4 rand = hash43x(ip*283.1); vec3 q2 = abs(p2);
        vec3 pl = 1.0- step(max(q2.x, max(q2.y, q2.z)), q2);
        vec3 pp = fp - ((rand.xyz-0.5)*.6 + 0.5)*pl;
        float pr = length(ip) - rad;   
        if (rand.w > (dens - dens*pr*0.035)) pp += 1e6;
        float d = dot(pp, pp) / (pow(fract(rand.w*172.1), 32.) + .25);
        float bri = dot(rand.xyz*(1.-pl),vec3(1));
        id = fract(rand.w*101.);
        col += bri*z*.00009/pow(d + 0.025, 3.0)*(mix(vec3(1.0,0.45,0.1),vec3(0.75,0.85,1.), id)*0.6+0.4);
        rad = floor(rad*1.08); dens *= 1.45; z *= 0.6; p = p.yxz;
    }
    return col;
}
// [MOD] 空间数字雨，字形构造参考 Inside the Matrix：
// https://www.shadertoy.com/view/4t3BWl
// 整数散列保持网格与字符种子的区别；时间只控制图案，不代表发射体运动。
#if iPolarization != 0
vec3 rainRadiance = vec3(0.0);
#endif
uint RainHash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    return x ^ (x >> 16);
}
uint RainSeed(ivec3 cell) {
    return RainHash(uint(cell.x) ^ RainHash(uint(cell.y)) ^ RainHash(uint(cell.z) + 0x9e3779b9u));
}
vec4 RainRandom(uint seed) {
    return vec4(uvec4(RainHash(seed), RainHash(seed+1u), RainHash(seed+2u), RainHash(seed+3u)) >> 8) / 16777216.0;
}
float RainRune(vec2 uv, uint seed, float highlight) {
    float distanceToLine = 1e5;
    for (int i=0; i<4; ++i) {
        vec4 p = RainRandom(seed + uint(i)*4u);
        if (i==0) p.y=0.0;
        if (i==1) p.x=0.999;
        if (i==2) p.x=0.0;
        if (i==3) p.y=0.999;
        p = (floor(p*vec4(2,3,2,3))+0.5)/vec4(2,3,2,3);
        vec2 line = p.zw-p.xy;
        float t = clamp(dot(uv-p.xy,line)/max(dot(line,line),1e-5),0.0,1.0);
        distanceToLine = min(distanceToLine,length(uv-p.xy-t*line));
    }
    return 1.0-smoothstep(0.0,0.1,distanceToLine)
         + highlight*(1.0-smoothstep(0.0,0.4,distanceToLine));
}
bool RainSheet(float universeSign) {
    return (iBlackHoleMassSol<0.0) != (universeSign<0.0);
}
bool RainVolumeSheet(float universeSign) {
#if ANTIVERSE_RAIN_3D == 1
    return RainSheet(universeSign);
#else
    return false;
#endif
}

// =============================================================================
// SECTION 2: 基础工具函数 (噪声、插值、随机)
// =============================================================================
float det3(vec3 a, vec3 b, vec3 c) {
    return dot(a, cross(b, c));
}
float RandomStep(vec2 Input, float Seed)
{
    return fract(sin(dot(Input + fract(11.4514 * sin(Seed)), vec2(12.9898, 78.233))) * 43758.5453);
}

float CubicInterpolate(float x) {
    return x * x * (3.0 - 2.0 * x);
}

float PerlinNoiseCell(vec3 PosInt, vec3 PosFloat, float NextX)
{
    float Sx = CubicInterpolate(PosFloat.x);
    float Sy = CubicInterpolate(PosFloat.y);
    float Sz = CubicInterpolate(PosFloat.z);
    
    float v000 = 2.0 * fract(sin(dot(vec3(PosInt.x,       PosInt.y,       PosInt.z),       vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v100 = 2.0 * fract(sin(dot(vec3(NextX,         PosInt.y,       PosInt.z),       vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v010 = 2.0 * fract(sin(dot(vec3(PosInt.x,       PosInt.y + 1.0, PosInt.z),       vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v110 = 2.0 * fract(sin(dot(vec3(NextX,         PosInt.y + 1.0, PosInt.z),       vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v001 = 2.0 * fract(sin(dot(vec3(PosInt.x,       PosInt.y,       PosInt.z + 1.0), vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v101 = 2.0 * fract(sin(dot(vec3(NextX,         PosInt.y,       PosInt.z + 1.0), vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v011 = 2.0 * fract(sin(dot(vec3(PosInt.x,       PosInt.y + 1.0, PosInt.z + 1.0), vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    float v111 = 2.0 * fract(sin(dot(vec3(NextX,         PosInt.y + 1.0, PosInt.z + 1.0), vec3(12.9898, 78.233, 213.765))) * 43758.5453) - 1.0;
    
    return mix(mix(mix(v000, v100, Sx), mix(v010, v110, Sx), Sy),
               mix(mix(v001, v101, Sx), mix(v011, v111, Sx), Sy), Sz);
}

float PerlinNoise(vec3 Position)//以后改成读lut
{
    vec3 PosInt = floor(Position);
    return PerlinNoiseCell(PosInt, fract(Position), PosInt.x + 1.0);
}

// 每层角向格点首尾相接，径向和竖直方向不作周期折返。
float InnerCloudNoise(vec2 PlanarPos, float Radius, float Height, float TimePhase)
{
    float Turns = fract((-atan(PlanarPos.y, PlanarPos.x) + (4.0 / 3.0) * TimePhase) / (2.0 * kPi));
    float NoiseAccumulator = 10.0;
    for (int i = 0; i < 6; i++) {
        float Frequency = pow(3.0, float(i));
        // 基频为每弧度 2.25 格；整圈格数逐层取整，细层不累积取整误差。
        float Period = floor(2.0 * kPi * 2.25 * Frequency + 0.5);
        vec3 Position = vec3(Turns * Period, Radius * Frequency, Height * Frequency);
        vec3 PosInt = floor(Position);
        if (PosInt.x >= Period) PosInt.x = 0.0;
        float NextX = PosInt.x + 1.0;
        if (NextX >= Period) NextX = 0.0;
        float Noise = PerlinNoiseCell(PosInt, fract(Position), NextX);
        NoiseAccumulator *= 1.0 + 0.1 * Noise;
    }
    return log(1.0 + pow(0.1 * NoiseAccumulator, 80.0));
}

float SoftSaturate(float x)
{
    return 1.0 - 1.0 / (max(x, 0.0) + 1.0);
}

float PerlinNoise1D(float Position)
{
    float PosInt   = floor(Position);
    float PosFloat = fract(Position);
    float v0 = 2.0 * fract(sin(PosInt * 12.9898) * 43758.5453) - 1.0;
    float v1 = 2.0 * fract(sin((PosInt + 1.0) * 12.9898) * 43758.5453) - 1.0;
    return v1 * CubicInterpolate(PosFloat) + v0 * CubicInterpolate(1.0 - PosFloat);
}

float GenerateAccretionDiskNoise(vec3 Position, float NoiseStartLevel, float NoiseEndLevel, float ContrastLevel)
{
    float NoiseAccumulator = 10.0;
    float start = NoiseStartLevel;
    float end = NoiseEndLevel;
    int iStart = int(floor(start));
    int iEnd = int(ceil(end));
    
    int maxIterations = iEnd - iStart;
    for (int delta = 0; delta < maxIterations; delta++)
    {
        int i = iStart + delta;
        float iFloat = float(i);
        float w = max(0.0, min(end, iFloat + 1.0) - max(start, iFloat));
        if (w <= 0.0) continue;
        
        float NoiseFrequency = pow(3.0, iFloat);
        vec3 ScaledPosition = NoiseFrequency * Position;
        float noise = PerlinNoise(ScaledPosition);
        NoiseAccumulator *= (1.0 + 0.1 * noise * w);
    }
    return log(1.0 + pow(0.1 * NoiseAccumulator, ContrastLevel));
}

float Vec2ToTheta(vec2 v1, vec2 v2)
{
    float VecDot   = dot(v1, v2);
    float VecCross = v1.x * v2.y - v1.y * v2.x;
    float Angle    = asin(0.999999 * VecCross / (length(v1) * length(v2)));
    float Dx = step(0.0, VecDot);
    float Cx = step(0.0, VecCross);
    return mix(mix(-kPi - Angle, kPi - Angle, Cx), Angle, Dx);
}

// 调用处的第二个向量由正弦和余弦构成，长度为 1。
float Vec2ToThetaUnit(float lengthV1, vec2 v1, vec2 v2)
{
    float VecDot = dot(v1, v2);
    float VecCross = v1.x * v2.y - v1.y * v2.x;
    float Angle = asin(0.999999 * VecCross / lengthV1);
    float Dx = step(0.0, VecDot);
    float Cx = step(0.0, VecCross);
    return mix(mix(-kPi - Angle, kPi - Angle, Cx), Angle, Dx);
}

float Shape(float x, float Alpha, float Beta)
{
    float k = pow(Alpha + Beta, Alpha + Beta) / (pow(Alpha, Alpha) * pow(Beta, Beta));
    return k * pow(x, Alpha) * pow(1.0 - x, Beta);
}



// =============================================================================
// SECTION 3: 颜色与光谱函数     采样与后处理
// =============================================================================

vec3 KelvinToRgb(float Kelvin)
{
    if (Kelvin < 400.01) return vec3(0.0);
    float Teff     = (Kelvin - 6500.0) / (6500.0 * Kelvin * 2.2);
    vec3  RgbColor = vec3(0.0);
    RgbColor.r = exp(2.05539304e4 * Teff);
    RgbColor.g = exp(2.63463675e4 * Teff);
    RgbColor.b = exp(3.30145739e4 * Teff);
    float BrightnessScale = 1.0 / max(max(1.5 * RgbColor.r, RgbColor.g), RgbColor.b);
    if (Kelvin < 1000.0) BrightnessScale *= (Kelvin - 400.0) / 600.0;
    RgbColor *= BrightnessScale;
    return RgbColor;
}

vec3 WavelengthToRgb(float wavelength) {
    // 分段线性光谱，波段交界由截断斜坡连接。
    vec3 color;
    color.r = clamp((440.0-wavelength)/60.0,0.0,1.0)
            + clamp((wavelength-510.0)/70.0,0.0,1.0);
    color.g = min(clamp((wavelength-440.0)/50.0,0.0,1.0),
                  clamp((645.0-wavelength)/65.0,0.0,1.0));
    color.b = clamp((510.0-wavelength)/20.0,0.0,1.0);
    float factor = clamp(min(0.3+0.7*(wavelength-380.0)/40.0,
                             0.3+0.7*(750.0-wavelength)/105.0),0.3,1.0);
    return color * factor / pow(color.r * color.r + 2.25 * color.g * color.g + 0.36 * color.b * color.b, 0.5) * (0.1 * (color.r + color.g + color.b) + 0.9);
}

// [MOD] 背景颜色沿黑体曲线频移，亮度由辐射传输因子单独控制。
#if BG_SHIFT_MODE == 2 || ANTIVERSE_SHIFT_MODE == 2
// 曲线坐标：s=u+v，固定色偏沿黑体曲线移动，高温端连续延拓
// 分段多项式约束端点及切线，数据来自 CIE 1931 积分
float BackgroundLogT(float s)
{
    if(s<4.5149342131e-01) {
        float L=-log(max((s-0.24)/(4.5149342131e-01-0.24),1e-20));
        return 1.0596634733e+01+2.0*L/(4.1249589350e-02+sqrt(4.1249589350e-02*4.1249589350e-02+8.0*L));
    }
    float t;
    if(s<4.6623122658e-01) {
        t=(s-4.5149342131e-01)*1.3570541632e+02-1.0;
        return (((((((((-2.9917776133e-04*t+6.5820320691e-04)*t+-6.8699596801e-04)*t+1.7661250618e-03)*t+-5.2919837167e-03)*t+1.3523303150e-02)*t+-3.6347967645e-02)*t+1.0809416557e-01)*t+-4.1551924085e-01)*t+1.0014447570e+01);
    }
    else if(s<5.1742438194e-01) {
        t=(s-4.6623122658e-01)*3.9067722741e+01-1.0;
        return (((((((((-8.1652842486e-04*t+1.6037820598e-03)*t+-1.0533201998e-03)*t+2.5961945879e-03)*t+-8.2048757242e-03)*t+1.8435589826e-02)*t+-4.2905859223e-02)*t+1.1104614887e-01)*t+-4.3743404293e-01)*t+9.0562476594e+00);
    }
    else if(s<6.2624224775e-01) {
        t=(s-5.1742438194e-01)*1.8379334912e+01-1.0;
        return (((((((((-7.3614269198e-05*t+1.8369800657e-04)*t+-2.7225763488e-04)*t+7.3895259304e-04)*t+-2.2094883734e-03)*t+6.2710752779e-03)*t+-1.8129920160e-02)*t+5.8332522267e-02)*t+-4.1704908824e-01)*t+8.1962541314e+00);
    }
    else {
        t=(s-6.2624224775e-01)*1.1338499027e+01-1.0;
        return (((((((((-4.0867961495e-06*t+-7.3117101351e-06)*t+-6.2374835599e-05)*t+2.4566770059e-04)*t+-8.4470063116e-04)*t+-2.4117155650e-04)*t+-8.8456868725e-03)*t+3.3422111572e-02)*t+-4.4838851680e-01)*t+7.3324813489e+00);
    }
}
vec2 BackgroundFrame(float q)
{
    if(q>1.0596634733e+01) {
        float u=q-1.0596634733e+01;
        float s=0.24+(4.5149342131e-01-0.24)*exp(-4.1249589350e-02*u-2.0*u*u);
        float t=s<0.28 ? s-0.24 : s-0.28;
        if(s<0.28) return vec2(s,(((-4.0625000000e+02*t+3.3125000000e+01)*t+2.0000000000e-01)*t+5.0000000000e-03));
        else return vec2(s,(((-3.3891703695e+01*t+8.3778990474e+00)*t+9.0000000000e-01)*t+4.0000000000e-02));
    }
    q=max(q,5.9914645471e+00);
    float t;
    if(q<7.0900768358e+00) {
        t=(q-5.9914645471e+00)*1.8204784533e+00-1.0;
        return vec2(((((((((1.4179547092e-04*t+-8.2980722826e-05)*t+-2.4163219020e-04)*t+-8.5169206261e-04)*t+6.7924526827e-04)*t+1.1098905265e-02)*t+-2.1286675134e-02)*t+-1.0369322620e-01)*t+8.7809874761e-01),((((((((-9.6759620218e-06*t+2.5736342667e-05)*t+1.4397436795e-05)*t+-4.1445158953e-05)*t+-4.0051945042e-04)*t+-1.6787220307e-03)*t+1.9612054221e-03)*t+1.1276086272e-02)*t+3.4680000835e-01));
    }
    else if(q<8.2940496401e+00) {
        t=(q-7.0900768358e+00)*1.6611670902e+00-1.0;
        return vec2(((((((((2.1319659607e-05*t+3.7374962102e-05)*t+-2.5346147727e-04)*t+1.4287766246e-04)*t+2.3994549017e-04)*t+7.4100443097e-04)*t+1.3480271495e-02)*t+-1.0310451734e-01)*t+6.4819115185e-01),((((((((2.2077684275e-05*t+2.5334271984e-05)*t+-2.3013551416e-04)*t+-1.7404568813e-04)*t+1.8556121227e-03)*t+1.0230288789e-03)*t+-1.2929002002e-02)*t+-1.2654565479e-02)*t+3.5744827091e-01));
    }
    else if(q<9.3926619288e+00) {
        t=(q-8.2940496401e+00)*1.8204784533e+00-1.0;
        return vec2(((((((((-5.1019637759e-07*t+-5.6982174699e-06)*t+1.2708091415e-05)*t+8.4496957146e-05)*t+-2.8478889217e-04)*t+-1.2571748525e-03)*t+1.1918569573e-02)*t+-4.0758668778e-02)*t+5.0591294327e-01),((((((((-8.7053554410e-07*t+-6.3671211515e-06)*t+2.9882310279e-05)*t+5.5472275875e-05)*t+-5.9273117841e-04)*t+9.7450137125e-04)*t+4.1614523361e-03)*t+-2.4331945152e-02)*t+3.0748050363e-01));
    }
    else {
        t=(q-9.3926619288e+00)*1.6611670902e+00-1.0;
        return vec2(((((((((-4.7769691491e-07*t+2.2647384972e-06)*t+-3.1784636561e-06)*t+-2.2027968532e-05)*t+2.1194066017e-04)*t+-1.1004623700e-03)*t+4.1315331248e-03)*t+-1.0944002223e-02)*t+4.5921783151e-01),((((((((-3.2699172969e-07*t+2.6375421619e-06)*t+-8.8643022116e-06)*t+8.2234079328e-06)*t+8.9209875320e-05)*t+-6.8422440246e-04)*t+2.9448349292e-03)*t+-8.3110117715e-03)*t+2.7576066920e-01));
    }
}
// 在黑体曲线附近，蓝移终点需要抵达 Rayleigh-Jeans 极限的蓝色
vec2 BackgroundStellarFrame(float q,vec2 extended)
{
    if(q<=1.0596634733e+01) return extended;
    float t=exp(1.0596634733e+01-q);
    return vec2(4.4358558047e-01,2.6352121736e-01)+t*(vec2(7.0916648973e-03,5.7268196550e-03)+t*vec2(8.1617594091e-04,5.5311047656e-04));
}

vec3 BackgroundShift(vec3 color,float shift)
{
    if(shift==1.0) return color;
    float peak=max(color.r,max(color.g,color.b));
    if(peak<=0.0) return vec3(0.0);
    vec3 inputColor=max(color/peak,vec3(0.0));
    vec3 xyz=mat3(4.1245640000e-01,2.1267290000e-01,1.9333900000e-02,3.5757610000e-01,7.1515220000e-01,1.1919200000e-01,1.8043750000e-01,7.2175000000e-02,9.5030410000e-01)*inputColor;
    float denominator=xyz.x+15.0*xyz.y+3.0*xyz.z;
    vec2 uv=vec2(4.0*xyz.x,6.0*xyz.y)/denominator;
    float s=uv.x+uv.y;
    float q=BackgroundLogT(s),delta=log(max(shift,1e-12));
    vec2 origin=BackgroundFrame(q),moved=BackgroundFrame(q+delta);
    // 只在高温延拓处分流，鲜艳且偏离黑体曲线的颜色才充分进入紫端
    float spectral=smoothstep(0.012,0.05,abs(uv.y-origin.y));
    origin=mix(BackgroundStellarFrame(q,origin),origin,spectral);
    moved=mix(BackgroundStellarFrame(q+delta,moved),moved,spectral);
    // 用差量锚定输入，使拟合误差不在 g=1 处形成接缝
    float sn=s+moved.x-origin.x;
    float width0=smoothstep(400.0,2000.0,exp(min(q,7.6009024595)));
    float width1=smoothstep(400.0,2000.0,exp(min(q+delta,7.6009024595)))*smoothstep(0.24,0.28,moved.x);
    float v=moved.y+(uv.y-origin.y)*width1/max(width0,1e-20);
    v=clamp(v,0.001,min(sn-0.001,(4.0-sn)/9.0-1e-7));
    float u=sn-v;
    vec3 raw=mat3(3.2404548360e+00,-9.6926638988e-01,5.5643419604e-02,-1.5371388501e+00,1.8760109288e+00,-2.0402585427e-01,-4.9853154687e-01,4.1556082347e-02,1.0572251625e+00)*vec3(1.5*u/v,1.0,(2.0-0.5*u-5.0*v)/v);
    // 连续压去色域外的负通道，保留亮度
    float e=0.01*(1.0-exp(-delta*delta/0.0144));
    vec3 mapped=max(0.5*(raw+sqrt(raw*raw+vec3(e*e))),vec3(0.0));
    return mapped*(xyz.y*peak/max(dot(mapped,vec3(0.2126729,0.7151522,0.0721750)),1e-30));
}
#endif


vec3 BackgroundChannelFloor(vec3 color, vec3 inputColor, float shift)
{
#if BG_SHIFT_WHITEN == 1
    float peak = max(color.r, max(color.g, color.b));
    float inputPeak = max(inputColor.r, max(inputColor.g, inputColor.b));
    float strength = smoothstep(BG_WHITEN_SHIFT.x, BG_WHITEN_SHIFT.y, shift)
                   * smoothstep(BG_WHITEN_BRIGHTNESS.x, BG_WHITEN_BRIGHTNESS.y, inputPeak);
    color = max(color, vec3(peak*BG_WHITEN_FLOOR*strength));
#endif
    return color;
}

// 两种背景各自选择色彩频移，亮度与低通道保底共用配置。
vec3 ThreeColorBackgroundShift(vec3 color, float shift)
{
    vec3 shifted = color.r * WavelengthToRgb(max(453.0, 645.0 / shift))
                 + color.g * 1.5 * WavelengthToRgb(max(416.0, 510.0 / shift))
                 + color.b * 0.6 * WavelengthToRgb(max(380.0, 440.0 / shift));
    return shifted * (dot(color, vec3(0.3, 0.6, 0.1))
                    / max(dot(shifted, vec3(0.3, 0.6, 0.1)), 0.001));
}

vec3 ShiftBackgroundColor(vec3 color, float shift, bool digitalRain)
{
    vec3 shifted;
    if (digitalRain) {
#if ANTIVERSE_SHIFT_MODE == 2
        shifted = BackgroundShift(color, shift);
#elif ANTIVERSE_SHIFT_MODE == 1
        shifted = ThreeColorBackgroundShift(color, shift);
#else
        #error ANTIVERSE_SHIFT_MODE must be 1 or 2
#endif
    } else {
#if BG_SHIFT_MODE == 2
        shifted = BackgroundShift(color, shift);
#elif BG_SHIFT_MODE == 1
        shifted = ThreeColorBackgroundShift(color, shift);
#else
        #error BG_SHIFT_MODE must be 1 or 2
#endif
    }
    return BackgroundChannelFloor(shifted, color, shift);
}

//                                                                    立体角比            入射立体角
#if ANTIVERSE_RAIN_3D == 0
vec3 SampleInfiniteRain(vec3 direction);
#endif
vec4 SampleBackground(vec3 Dir, float Shift, float Status, float Magnification, float ScreenSolidAngle)
{
    float rStatus = round(Status);
    int universeOffset = rStatus > 3.0 ? int(round((rStatus - 1.0) / 3.0)) : 0;
    int backgroundIndex = int(mod(float(iInWhichUniverse - universeOffset), 3.0));
    float angle = float(backgroundIndex) * (2.0 * kPi / 3.0);
    vec3 skyDir = vec3(cos(angle) * Dir.x + sin(angle) * Dir.z, Dir.y,
                       -sin(angle) * Dir.x + cos(angle) * Dir.z);
    bool isNegativeMass = iBlackHoleMassSol < 0.0;
    bool isAntiverse = mod(rStatus, 3.0) == 2.0;
    vec4 Backcolor;
    if (isNegativeMass != isAntiverse) {
#if ANTIVERSE_RAIN_3D == 1
        return vec4(0.0); // 数字雨已沿空间光路合成。
#else
        Backcolor=vec4(SampleInfiniteRain(skyDir),1.0);
#endif
    } else Backcolor=vec4(stars(skyDir),1.0);

    if (iPointSourceBrightening == 1) {
        float omegaStar = 0.1 * ScreenSolidAngle;
        float maxMagnification = ScreenSolidAngle / max(omegaStar, 1e-12);
        float pointSourceMask = smoothstep(0.5, 0.7, max(max(Backcolor.r, Backcolor.g), Backcolor.b));
        Backcolor.rgb *= mix(1.0, min(Magnification, maxMagnification), pointSourceMask);
    }

    vec3 Scolor = ShiftBackgroundColor(Backcolor.rgb, Shift, isNegativeMass != isAntiverse);
    if (isNegativeMass == isAntiverse) {
        // 星空先频移，再按三组宇宙编号着色：后一宇宙偏蓝，前一宇宙偏红。
        if (backgroundIndex == 1) Scolor *= vec3(0.2, 0.4, 1.0);
        else if (backgroundIndex == 2) Scolor *= vec3(1.0, 0.4, 0.2);
        // 平行宇宙将着色后的色相旋转 180°，保持最大、最小通道值。
        if (abs(Status - rStatus) > 0.1) {
            float cMax = max(max(Scolor.r, Scolor.g), Scolor.b);
            float cMin = min(min(Scolor.r, Scolor.g), Scolor.b);
            Scolor = vec3(cMax + cMin) - Scolor;
        }
    }
    return iBackgroundBrightmut * vec4(Scolor, Backcolor.a) * pow(Shift, 4.0);
}

vec4 ApplyToneMapping(vec4 Result,float shift) {
    float RedFactor   = 3.0 * Result.r / (Result.r + Result.b + Result.g + 1e-6);
    float BlueFactor  = 3.0 * Result.b / (Result.r + Result.b + Result.g + 1e-6);
    float GreenFactor = 3.0 * Result.g / (Result.r + Result.b + Result.g + 1e-6);
    float BloomMax    = max(8.0, shift) + log(max(shift - 8.0 + 1.0, 1.0));
    vec4 Mapped;
    Mapped.r = min(-4.0 * log(1.0 - pow(clamp(Result.r, 0.0, 0.999), 2.2)), BloomMax * RedFactor);
    Mapped.g = min(-4.0 * log(1.0 - pow(clamp(Result.g, 0.0, 0.999), 2.2)), BloomMax * GreenFactor);
    Mapped.b = min(-4.0 * log(1.0 - pow(clamp(Result.b, 0.0, 0.999), 2.2)), BloomMax * BlueFactor);
    Mapped.a = min(-4.0 * log(1.0 - pow(clamp(Result.a, 0.0, 0.999), 2.2)), 4.0);
    return Mapped;
}
// =============================================================================
// SECTION 4: 广相计算。Y为自旋方向，ins/outgoing方向笛卡尔形式kerrscild系。+++-。
// =============================================================================

const float CONST_M = 0.5; // [PHYS] Mass M = 0.5
const float EPSILON = 1e-6;

// [TENSOR] Flat Space Metric eta_uv = diag(1, 1, 1, -1)
const mat4 MINKOWSKI_METRIC = mat4(
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, -1
);

//PhysicalSpinA和PhysicalQ2是有量纲量（无量纲量乘M/M2，即乘0.5/0.25）。

float GetKeplerianAngularVelocity(float Radius, float Rs, float PhysicalSpinA, float PhysicalQ2) 
{
    float M = 0.5 * Rs; 
    float Mr_minus_Q2 = M * Radius - PhysicalQ2;
    if (Mr_minus_Q2 < 0.0) return 0.0;
    float sqrt_Term = sqrt(Mr_minus_Q2);
    float denominator = Radius * Radius + PhysicalSpinA * sqrt_Term;
    return sqrt_Term / max(EPSILON, denominator);
}
//PhysicalSpinA和PhysicalQ2是有量纲量
//输入X^mu空间部分，输出bl系参数r
float KerrSchildRadius(vec3 p, float PhysicalSpinA, float r_sign) {
    float r_sign_len = r_sign * length(p);
    if (PhysicalSpinA == 0.0) return r_sign_len; 

    float a2 = PhysicalSpinA * PhysicalSpinA;
    float rho2 = dot(p.xz, p.xz); // x^2 + z^2
    float y2 = p.y * p.y;
    
    float b = rho2 + y2 - a2;
    float det = sqrt(b * b + 4.0 * a2 * y2);
    
    float r2;
    if (b >= 0.0) {
        r2 = 0.5 * (b + det);
    } else {
        r2 = (2.0 * a2 * y2) / max(1e-20, det - b);
    }
    return r_sign * sqrt(r2);
}
// 返回外、内视界的有符号半径；调用处另行检查视界是否存在。
vec2 KerrHorizonRadii(float a, float Q2) {
    float SpinCharge = a * a + Q2;
    float OuterR = CONST_M + sqrt(max(0.0, CONST_M * CONST_M - SpinCharge));
    return vec2(OuterR, SpinCharge / OuterR);
}
// 计算 ZAMO (零角动量观测者) 的角速度 Omega
float GetZamoOmega(float r, float a, float Q2, float y) {
    float r2 = r * r;
    float a2 = a * a;
    float y2 = y * y;
    float cos2 = min(1.0, y2 / (r2 + 1e-9)); 
    float sin2 = 1.0 - cos2;
    
    // Delta = r^2 - 2Mr + a^2 + Q^2 (M=0.5)
    float Delta = r2 - r + a2 + Q2;
    
    // Sigma = r^2 + a^2 cos^2 theta
    float Sigma = r2 + a2 * cos2;
    
    // metric term A = (r^2+a^2)^2 - Delta * a^2 * sin^2 theta
    float A_metric = (r2 + a2) * (r2 + a2) - Delta * a2 * sin2;
    
    // Omega_ZAMO = 2Mra / A (for Q=0), with Q: a(2Mr - Q^2) / A
    // 2Mr = r (since M=0.5, 2M=1.0) -> r
    return a * (r - Q2) / max(1e-9, A_metric);
}

// 求解射线与 Kerr-Schild 常数 r 椭球面的交点
// 方程: (x^2 + z^2)/(r^2 + a^2) + y^2/r^2 = 1
// 返回 vec2(t1, t2)，如果没有交点返回 vec2(-1.0)
vec2 IntersectKerrEllipsoid(vec3 O, vec3 D, float r, float a) {
    float r2 = r * r;
    float a2 = a * a;
    float R_eq_sq = r2 + a2; // 赤道半径平方
    float R_pol_sq = r2;     // 极半径平方
    
    // 椭球方程: B(x^2 + z^2) + A(y^2) = A*B
    // 其中 A = R_eq_sq, B = R_pol_sq
    float A = R_eq_sq;
    float B = R_pol_sq;
    
    // 代入射线 P = O + D*t
    // (B*Dx^2 + B*Dz^2 + A*Dy^2) t^2 + ...
    float qa = B * (D.x * D.x + D.z * D.z) + A * D.y * D.y;
    float qb = 2.0 * (B * (O.x * D.x + O.z * D.z) + A * O.y * D.y);
    float qc = B * (O.x * O.x + O.z * O.z) + A * O.y * O.y - A * B;
    
    if (abs(qa) < 1e-9) return vec2(-1.0); // 线性退化，忽略
    
    float disc = qb * qb - 4.0 * qa * qc;
    if (disc < 0.0) return vec2(-1.0);
    
    float sqrtDisc = sqrt(disc);
    float t1 = (-qb - sqrtDisc) / (2.0 * qa);
    float t2 = (-qb + sqrtDisc) / (2.0 * qa);
    
    return vec2(t1, t2);
}

struct KerrGeometry {
    float r;
    float r2;
    float a2;
    float f;              
    vec3  grad_r;         
    vec3  grad_f;         
    vec4  l_up;           // l^u = (lx, ly, lz, -1)
    vec4  l_down;         // l_u = (lx, ly, lz, 1)
    float inv_r2_a2;
    float inv_den_f;      
    float num_f;          
};

//fade用于在接近包围盒边界时强行过渡为平直时空。直接乘在f上。下文中gravityfade同。

void ComputeGeometryScalars(vec3 X, float PhysicalSpinA, float PhysicalQ2, float fade, float r_sign, bool isOutgoing, out KerrGeometry geo) {
    geo.a2 = PhysicalSpinA * PhysicalSpinA;
    
    // 决定流入还是流出
    float dirSign = isOutgoing ? -1.0 : 1.0;
    
    if (PhysicalSpinA == 0.0) {
        geo.r = r_sign * length(X);
        geo.r2 = geo.r * geo.r;
        float inv_r = 1.0 / geo.r;
        float inv_r2 = inv_r * inv_r;
        
        // 乘上 dirSign
        geo.l_up = vec4(dirSign * X * inv_r, -1.0);
        geo.l_down = vec4(dirSign * X * inv_r, 1.0);
        
        geo.num_f = (2.0 * CONST_M * geo.r - PhysicalQ2);
        geo.f = (2.0 * CONST_M * inv_r - (PhysicalQ2) * inv_r2) * fade;
        
        geo.inv_r2_a2 = inv_r2; 
        geo.inv_den_f = inv_r2 * inv_r2; 
        return;
    }

    geo.r = KerrSchildRadius(X, PhysicalSpinA, r_sign);
    geo.r2 = geo.r * geo.r;
    float r3 = geo.r2 * geo.r;
    float z_coord = X.y; 
    float z2 = z_coord * z_coord;
    
    geo.inv_r2_a2 = 1.0 / (geo.r2 + geo.a2);
    
    // 向外/向内仅反转径向成分，保留自旋成分
    float lx = (dirSign * geo.r * X.x - PhysicalSpinA * X.z) * geo.inv_r2_a2;
    float ly = (dirSign * X.y) / geo.r;
    float lz = (dirSign * geo.r * X.z + PhysicalSpinA * X.x) * geo.inv_r2_a2;
    
    geo.l_up = vec4(lx, ly, lz, -1.0);
    geo.l_down = vec4(lx, ly, lz, 1.0); 
    
    geo.num_f = 2.0 * CONST_M * r3 - PhysicalQ2 * geo.r2;
    float den_f = geo.r2 * geo.r2 + geo.a2 * z2;
    geo.inv_den_f = 1.0 / max(1e-20, den_f);
    geo.f = (geo.num_f * geo.inv_den_f) * fade;
}


void ComputeGeometryGradients(vec3 X, float PhysicalSpinA, float PhysicalQ2, float fade, inout KerrGeometry geo) {
    float inv_r = 1.0 / geo.r;
    
    if (PhysicalSpinA == 0.0) {

        float inv_r2 = inv_r * inv_r;
        geo.grad_r = X * inv_r;
        float df_dr = (-2.0 * CONST_M + 2.0 * PhysicalQ2 * inv_r) * inv_r2 * fade;
        geo.grad_f = df_dr * geo.grad_r;
        return;
    }

    float inv_denom_grad = geo.r * geo.inv_den_f;
    
    geo.grad_r = vec3(
        X.x * geo.r2,
        X.y * (geo.r2 + geo.a2),
        X.z * geo.r2
    ) * inv_denom_grad;
    
    float z_coord = X.y;
    float z2 = z_coord * z_coord;
    
    float term_M  = -2.0 * CONST_M * geo.r2 * geo.r2 * geo.r;
    float term_Q  = 2.0 * PhysicalQ2 * geo.r2 * geo.r2;
    float term_Ma = 6.0 * CONST_M * geo.a2 * geo.r * z2;
    float term_Qa = -2.0 * PhysicalQ2 * geo.a2 * z2;
    
    float df_dr_num_reduced = term_M + term_Q + term_Ma + term_Qa;
    float df_dr = (geo.r * df_dr_num_reduced) * (geo.inv_den_f * geo.inv_den_f);
    
    float df_dy = -(geo.num_f * 2.0 * geo.a2 * z_coord) * (geo.inv_den_f * geo.inv_den_f);
    
    geo.grad_f = df_dr * geo.grad_r;
    geo.grad_f.y += df_dy;
    geo.grad_f *= fade;
}

//ks系的形式使得度规与矢量的乘法可以优化
//升指标和降指标。虽然变量名用的P，但是可以用于任何符合变换规则的矢量
//  P^u = g^uv P_v
// g^uv = eta^uv - f * l^u * l^v
vec4 RaiseIndex(vec4 P_cov, KerrGeometry geo) {
    // eta^uv = diag(1, 1, 1, -1)
    vec4 P_flat = vec4(P_cov.xyz, -P_cov.w); 

    float L_dot_P = dot(geo.l_up, P_cov);
    
    return P_flat - geo.f * L_dot_P * geo.l_up;
}

// P_u = g_uv P^v
// g_uv = eta_uv + f * l_u * l_v
vec4 LowerIndex(vec4 P_contra, KerrGeometry geo) {
    // eta_uv = diag(1, 1, 1, -1)
    vec4 P_flat = vec4(P_contra.xyz, -P_contra.w);
    
    float L_dot_P = dot(geo.l_down, P_contra);
    
    return P_flat + geo.f * L_dot_P * geo.l_down;
}

//inout换系

// 物理常量与数值容差定义
const float EPS = 1e-16; // 防止除0和对数域爆炸的安全容差

//
// 笛卡尔 Kerr-Schild 坐标系 Ingoing/Outgoing 相互变换 (Y轴自旋版)
// 
// @param X          inout: 四坐标 (x, y, z, T)  (注：y为自旋轴)
// @param r_sign     in:    径向符号 (+1.0 或 -1.0)
// @param P          inout: 协变四动量 (p_x, p_y, p_z, p_T)
// @param M, a, Q    in:    黑洞三毛参数
// @param out_to_in  in:    false: In->Out;  true: Out->In
//
void transformKerrSchild_YSpin(inout vec4 X, in float r_sign, inout vec4 P, 
                               in float M, in float a, in float Q2, in bool out_to_in) 
{
    // 1. 提取变量
    float x = X.x, y = X.y, z = X.z, t = X.w;
    float px = P.x, py = P.y, pz = P.z, pt = P.w;
    
    float a2 = a * a;
    float M2 = M * M;

    // 2. 解径向方程求 r (Y 为自旋轴)
    float R2 = x*x + y*y + z*z;
    float u = R2 - a2;
    float v = 4.0 * a2 * y * y; 
    
    float r2;
    if (u >= 0.0) {
        r2 = 0.5 * (u + sqrt(u*u + v));
    } else {
        r2 = 0.5 * v / max(1e-20, sqrt(u*u + v) - u);
    }
    
    float r = r_sign * sqrt(max(r2, 0.0));

    // 3. 计算视界函数 Delta 与空间底度规项 D
    float Delta = r*r - 2.0*M*r + a2 + Q2;
    float safe_Delta = sign(Delta) * max(abs(Delta), EPS);
    if (safe_Delta == 0.0) safe_Delta = EPS;

    float r3 = r * r * r;
    float D = r3 * r + a2 * y * y; // r^4 + a^2 y^2
    float safe_D = max(D, 1e-12);

    // 4. 计算径向坐标的梯度 r_i (经过 x->z, y->x, z->y 置换)
    vec3 grad_r = vec3(
        r3 * x / safe_D,                 // 对应原 y 的梯度形式
        r * (r*r + a2) * y / safe_D,     // 对应原 z 的梯度形式 (极轴方向)
        r3 * z / safe_D                  // 对应原 x 的梯度形式
    );

    // 5. 分析黑洞类型并计算积分函数 F(r) 和 g(r)
    float delta_disc = M2 - (a2 + Q2); 
    float F_r = 0.0;
    float g_r = 0.0;
    float abs_Delta_safe = max(abs(Delta), EPS);

    if (delta_disc > EPS) {
        // [情形 A: 非极端黑洞]
        float K = sqrt(delta_disc);
        float r_plus = M + K;
        float r_minus = (a2 + Q2) / r_plus;
        
        float frac = abs(r - r_plus) / max(abs(r - r_minus), EPS);
        float ln_arg = log(max(frac, EPS));
        float ln_Delta = log(abs_Delta_safe);

        F_r = 2.0 * M * ln_Delta + ((2.0 * M2 - Q2) / K) * ln_arg;
        g_r = (a / K) * ln_arg;
        
    } else if (delta_disc < -EPS) {
        // [情形 B: 裸奇点 (无视界)]
        float K = sqrt(-delta_disc);
        float ln_Delta = log(abs_Delta_safe);
        float atan_arg = atan((r - M) / K);

        F_r = 2.0 * M * ln_Delta + (2.0 * (2.0 * M2 - Q2) / K) * atan_arg;
        g_r = (2.0 * a / K) * atan_arg;
        
    } else {
        // [情形 C: 极端黑洞]
        float rM = r - M;
        float safe_rM = sign(rM) * max(abs(rM), EPS);
        if (safe_rM == 0.0) safe_rM = EPS;
        float ln_rM = log(max(abs(rM), EPS));

        F_r = 4.0 * M * ln_rM - 2.0 * (2.0 * M2 - Q2) / safe_rM;
        g_r = -2.0 * a / safe_rM;
    }

    g_r += 2.0 * atan(a, r); 
    // 6. 计算导数与动量标量 K_p
    float F_prime = 2.0 * (2.0 * M * r - Q2) / safe_Delta;
    
    float g_prime = 2.0 * a / safe_Delta - 2.0 * a / (r * r + a * a);

    // 角动量 Ly (自旋轴为 y，对应的轨道角动量守恒量)
    float Ly = z * px - x * pz; 
    float K_p = F_prime * pt + g_prime * Ly;

    // 7. 处理换系方向逻辑
    float dir = out_to_in ? -1.0 : 1.0; 
    
    // 旋转角与时间延迟
    float angle      = -dir * g_r;
    float time_shift = -dir * F_r;
    
    // 8. 根据径向梯度修正空间动量
    vec3 P_tilde = vec3(px, py, pz) + dir * grad_r * K_p;

    // 9. 旋转矩阵 (作用于 Z-X 平面，绕 Y 轴)
    float cos_a = cos(angle);
    float sin_a = sin(angle);

    // 10. 赋值回原变量 (应用 Z-X 平面的旋转和时间偏移)
    X.x = x * cos_a + z * sin_a; // 原公式的 y'
    X.y = y;                     // Y 坐标(自旋轴)不变
    X.z = z * cos_a - x * sin_a; // 原公式的 x'
    X.w = t + time_shift;

    P.x =   P_tilde.z * sin_a + P_tilde.x * cos_a;
    P.y =   P_tilde.y;             // P_y(自旋方向动量)不变
    P.z = - P_tilde.x * sin_a + P_tilde.z * cos_a;
    P.w = pt;                    // 能量 Pt 不变
}
// E=1、L_y=0、Carter Q=0 的中性自由落体观者四速
vec4 GetFreeFallVelocity(vec3 X, KerrGeometry geo, bool isOutgoing)
{
    if (geo.f <= 0.0) {
        return vec4(0.0, 0.0, 0.0, inversesqrt(1.0 - geo.f));
    }

    float CosTheta = X.y / geo.r;
    float Sigma = geo.r2 + geo.a2 * CosTheta * CosTheta;
    float RadiusTerm = geo.r2 + geo.a2;
    float MassChargeTerm = geo.f * Sigma;
    float FallSpeed = sqrt(MassChargeTerm / RadiusTerm);
    float Denom = 1.0 + FallSpeed;

    if (isOutgoing) {
        Denom = (RadiusTerm - MassChargeTerm) / (RadiusTerm * Denom);
        if (Denom == 0.0) return vec4(114514.0);
    }

    vec3 GradR = vec3(
        geo.r * X.x,
        RadiusTerm * CosTheta,
        geo.r * X.z
    ) / Sigma;

    vec4 U_down = vec4((-FallSpeed / Denom) * GradR, -1.0);

    return RaiseIndex(U_down, geo);
}
//初始化ingoing系下光子动量P_u，以向心矢量为主轴做施密特正交化
vec4 GetInitialMomentum(
    vec3 RayDir,          
    vec4 X,               
    int  iObserverMode,   
    float universesign,
    float PhysicalSpinA,  
    float PhysicalQ2,      
    float GravityFade,
    bool isOutgoing
)
{
    if (iObserverMode == -1) {
        // 在 C++ 中，RayDir传入的是 ViewDirLocal（屏幕视锥方向）
        vec3 v = normalize(RayDir);
        
        // 利用平移输运过来的标架生成光子的四维动量
        vec4 P_up_cam = iU_up + v.x * ie1_up + v.y * ie2_up + v.z * ie3_up;
        
        bool camIsOutgoing = (iCamDataCoordisOutgoing == 1);
        
        // 获取相机所在系的度规
        KerrGeometry geo_cam;
        ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, universesign, camIsOutgoing, geo_cam);
        
        // 降为下指标动量
        vec4 P_cov_cam = LowerIndex(P_up_cam, geo_cam);
        
        // 如果 Shader 当前要求评估的系 (isOutgoing) 与相机所在系不一致，在此换系
        if (isOutgoing != camIsOutgoing) {
            vec4 dummyX = X;
            transformKerrSchild_YSpin(dummyX, universesign, P_cov_cam, CONST_M, PhysicalSpinA, PhysicalQ2, isOutgoing);
        }
        
        return P_cov_cam;
    }
    KerrGeometry geo;
    ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, universesign,isOutgoing, geo);

    //确定观者四维速度 U_up 
    vec4 U_up;
    // Static Observer
    float g_tt = -1.0 + geo.f;
    float time_comp = 1.0 / sqrt(max(1e-9, -g_tt));
    U_up = vec4(0.0, 0.0, 0.0, time_comp);
    if (iObserverMode == 1) {
        U_up = GetFreeFallVelocity(X.xyz, geo, isOutgoing);
    }else if (iObserverMode == 2) {
        // 模式 2 的按键指定局部目标速度，观者四速由相机积分提供。
        vec4 U_down = LowerIndex(iU_up, geo);
        float U_sq = dot(iU_up, U_down);
        if (U_sq < 0.0 && !any(isnan(iU_up)) && !any(isinf(iU_up))) {
            U_up = iU_up * inversesqrt(-U_sq);
        } else {
            return vec4(114514.0);
        }
    }
       
    vec4 U_down = LowerIndex(U_up, geo);

    //构建平直空间参考基
    //主轴，径向
    vec3 m_r = -normalize(X.xyz);

    vec3 WorldUp = vec3(0.0, 1.0, 0.0);
    //副轴，环向或X。注意这个系只是中转，在极点强取方向不会改变视线朝向，只会改变畸变方向，而两极处在平行赤道面上正好没有畸变
    if (abs(dot(m_r, WorldUp)) > 0.999) {
        WorldUp = vec3(1.0, 0.0, 0.0);
    }
    vec3 m_phi = cross(WorldUp, m_r); 
    m_phi = normalize(m_phi);

    vec3 m_theta = cross(m_phi, m_r); 

    // 分解 RayDir 到这组基底
    float k_r     = dot(RayDir, m_r);
    float k_theta = dot(RayDir, m_theta);
    float k_phi   = dot(RayDir, m_phi);

    //构建弯曲时空物理基底

    vec4 e1 = vec4(m_r, 0.0);
    e1 += dot(e1, U_down) * U_up; 
    vec4 e1_d = LowerIndex(e1, geo);
    float n1 = sqrt(max(1e-9, dot(e1, e1_d)));
    e1 /= n1; e1_d /= n1;

    vec4 e2 = vec4(m_theta, 0.0);
    e2 += dot(e2, U_down) * U_up;
    e2 -= dot(e2, e1_d) * e1;
    vec4 e2_d = LowerIndex(e2, geo);
    float n2 = sqrt(max(1e-9, dot(e2, e2_d)));
    e2 /= n2; e2_d /= n2;

    vec4 e3 = vec4(m_phi, 0.0);
    e3 += dot(e3, U_down) * U_up;
    e3 -= dot(e3, e1_d) * e1;
    e3 -= dot(e3, e2_d) * e2;
    vec4 e3_d = LowerIndex(e3, geo);
    float n3 = sqrt(max(1e-9, dot(e3, e3_d)));
    e3 /= n3;



    vec4 P_up = U_up - (k_r * e1 + k_theta * e2 + k_phi * e3);

    // 返回协变动量 P_mu
    return LowerIndex(P_up, geo);
}
// =============================================================================
// 调试函数：检查初始动量合法性并可视化局部动量方向
// =============================================================================
vec3 DebugInitialMomentum(
    vec4 P_cov, 
    vec4 X, 
    int ObserverMode, 
    float universesign, 
    float PhysicalSpinA, 
    float PhysicalQ2, 
    float GravityFade, 
    bool isOutgoing, 
    vec3 CameraVelocity
) {
    if (P_cov == vec4(114514.0)) return vec3(0.0);

    KerrGeometry geo;
    ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, universesign, isOutgoing, geo);

    // 升指标得到逆变动量，计算模长平方（测试类光条件）
    vec4 P_up = RaiseIndex(P_cov, geo);
    float norm_sq = dot(P_cov, P_up);

    // ====================================
    // 重建观者四维速度和局部平直标架
    // ====================================
    vec4 U_up;
    float g_tt = -1.0 + geo.f;
    float time_comp = 1.0 / sqrt(max(1e-9, -g_tt));
    U_up = vec4(0.0, 0.0, 0.0, time_comp);
    
    if (ObserverMode == 1) {
        U_up = GetFreeFallVelocity(X.xyz, geo, isOutgoing);
    } else if (ObserverMode == 2) {
        U_up = iU_up;
    }
    vec4 U_down = LowerIndex(U_up, geo);

    vec3 m_r = -normalize(X.xyz);
    vec3 WorldUp = vec3(0.0, 1.0, 0.0);
    if (abs(dot(m_r, WorldUp)) > 0.999) WorldUp = vec3(1.0, 0.0, 0.0);
    vec3 m_phi = normalize(cross(WorldUp, m_r)); 
    vec3 m_theta = cross(m_phi, m_r); 

    vec4 e1 = vec4(m_r, 0.0); e1 += dot(e1, U_down) * U_up; vec4 e1_d = LowerIndex(e1, geo); float n1 = sqrt(max(1e-9, dot(e1, e1_d))); e1 /= n1; e1_d /= n1;
    vec4 e2 = vec4(m_theta, 0.0); e2 += dot(e2, U_down) * U_up; e2 -= dot(e2, e1_d) * e1; vec4 e2_d = LowerIndex(e2, geo); float n2 = sqrt(max(1e-9, dot(e2, e2_d))); e2 /= n2; e2_d /= n2;
    vec4 e3 = vec4(m_phi, 0.0); e3 += dot(e3, U_down) * U_up; e3 -= dot(e3, e1_d) * e1; e3 -= dot(e3, e2_d) * e2; vec4 e3_d = LowerIndex(e3, geo); e3 /= sqrt(max(1e-9, dot(e3, e3_d)));

    // ====================================
    // 合法性检查与局部方向投影
    // ====================================
    // 计算光在观者局部正交标架下的空间动量: P_local^i = P_mu e_i^mu
    vec3 p_local = vec3(dot(P_cov, e1), dot(P_cov, e2), dot(P_cov, e3));
    vec3 local_dir = normalize(p_local); 

    // r通道：检查所有约束条件是否满足
    bool is_lightlike = abs(norm_sq) < 1e-4;    // 约束1：必须严格类光
    float E_loc = -dot(P_cov, U_up);
    bool is_energy_pos = true;//E_loc > 0.0;           // 约束2：观者测量的局部能量必须为正
    bool is_forward = true;//P_up.w > 0.0;             // 约束3：坐标时间分量一般向未来流动

    float valid_r = (is_lightlike && is_energy_pos && is_forward) ? 1.0 : 0.0;

    // g,b通道：将局部光线的x、y方向投影到 [0, 1] 颜色区间
    float g_chan = local_dir.x * 0.5 + 0.5;
    float b_chan = local_dir.y * 0.5 + 0.5;

    return vec3(valid_r, g_chan, b_chan);
}



// =============================================================================
// Walker-Penrose 常数计算 (无坐标奇点优化版)
// 输入:
//   X:     光子位置 (Cartesian KS, Y轴为自旋轴)
//   P_cov: 光子下指标动量 P_mu
//   F_cov: 光子下指标偏振 f_mu
//   Physicala: 有量纲自旋参数（0.5a*）,M=0.5
//   PhysicalQ2: 有量纲电荷参数平方（0.25(Q*)^2）
//   r:     由 KerrSchildRadius 算得的有符号半径
// 返回:
//   vec2:  Walker-Penrose 常数的 (实部, 虚部)
// =============================================================================
vec2 GetWalkerPenrose(vec4 X, vec4 P_cov, vec4 F_cov, float Physicala, float PhysicalQ2, float r) {
    // 提取坐标成分
    float x = X.x;
    float y = X.y;
    float z = X.z;
    
    // 提取下指标动量与偏振成分
    float px = P_cov.x;
    float py = P_cov.y;
    float pz = P_cov.z;
    float pt = P_cov.w; // 时间分量 P_t
    
    float fx = F_cov.x;
    float fy = F_cov.y;
    float fz = F_cov.z;
    float ft = F_cov.w; // 时间分量 F_t
    
    // 由于 Kerr-Schild 坐标系的特殊性质，其复 Killing-Yano 张量的逆变分量 Y^uv 
    // 与平直时空完全相同（H l^u l^v 项的缩并严格为0）。
    // 因此我们可以直接使用平直时空的逆变度规提升指标计算守恒量。
    // 在度规 +++- 符号下，P^i = P_i, P^t = -P_t。
    
    // 定义电型自旋向量 S_E^i = P^t F^i - F^t P^i = (-P_t) F_i - (-F_t) P_i = F_t P_i - P_t F_i
    float S_Ex = ft * px - pt * fx;
    float S_Ey = ft * py - pt * fy;
    float S_Ez = ft * pz - pt * fz;
    
    // 定义磁型自旋向量 S_B^i = (P \times F)^i (纯空间叉乘)
    float S_Bx = py * fz - pz * fy;
    float S_By = pz * fx - px * fz;
    float S_Bz = px * fy - py * fx;
    
    float a = Physicala;
    
    // 自旋方向为 Y 轴，即 a 向量为 (0, a, 0)
    // 根据平直时空 Y_uv P^u F^v 缩并推导：
    
    // K_1 (实部) = - [ a \cdot S_E + r \cdot S_B ]
    float K_re = a * S_Ey - (x * S_Bx + y * S_By + z * S_Bz);
    // K_2 (虚部) = - [ r \cdot S_E + a \cdot S_B ]
    float K_im = -(x * S_Ex + y * S_Ey + z * S_Ez + a * S_By);
    
    return vec2(K_re, K_im);
}
// 求解偏振在屏幕XY轴的投影
//vec2 SolvePolarization(vec2 W_emit, vec2 W_X, vec2 W_Y) {
//    float det = W_X.x * W_Y.y - W_X.y * W_Y.x;
//    if (abs(det) < 1e-9) return vec2(1.0, 0.0); // 奇异退化保护
//    float c1 = (W_emit.x * W_Y.y - W_emit.y * W_Y.x) / det;
//    float c2 = (W_X.x * W_emit.y - W_X.y * W_emit.x) / det;
//    return vec2(c1, c2);
//}
// =============================================================================
// 解算偏振在相机屏幕上的二维投影
// 输入:
//   K_photon: 当前光子射线携带的 Walker-Penrose 常数 (x:实部, y:虚部)
//   K_right:  相机“右”基向量 (Camera Right) 对应的 WP 常数
//   K_up:     相机“上”基向量 (Camera Up) 对应的 WP 常数
// 返回:
//   vec2:     偏振在相机屏幕上的投影系数 (alpha, beta)，即 (X屏幕分量, Y屏幕分量)
// =============================================================================
// =============================================================================
// 解算偏振在相机屏幕上的二维投影 (科学严谨版：基于守恒律的投影归一化)
// =============================================================================
vec2 SolvePolarization(vec2 K_photon, vec2 K_right, vec2 K_up) {
    float det = K_right.x * K_up.y - K_right.y * K_up.x;
    
    // 降低退化阈值。在 Float32 下，det 可能会小到 1e-20 量级
    if (abs(det) < 1e-25) {
        return vec2(1.0, 0.0); 
    }
    
    float inv_det = 1.0 / det;
    
    float alpha = ( K_up.y * K_photon.x - K_up.x * K_photon.y) * inv_det;
    float beta  = (-K_right.y * K_photon.x + K_right.x * K_photon.y) * inv_det;
    
    vec2 result = vec2(alpha, beta);
    
    // 【核心修复】：物理守恒律约束
    // 平行移动保持极化矢量的模长不变。因为发射点和相机处的极化基底均已归一化，
    // 理论上必定有 alpha^2 + beta^2 = 1。
    // Float32 在处理趋近径向光线的 WP 常数时发生灾难性相消，导致振幅失真甚至爆炸。
    // 在此将结果重新归一化，既消除了数值发散，又保留了精确的偏振方向（相位）信息。
    float mag = length(result);
    if (mag > 1e-19) {
        result /= mag;
    } else {
        // 如果连方向都被噪声完全摧毁(极其罕见)，指定一个默认方向
        result = vec2(1.0, 0.0);
    }
    
    return result;
}


// =============================================================================
// 5.积分器
// =============================================================================
struct State {
    vec4 X; // x^u
    vec4 P; // p_u
};

//固定守恒能量，修正动量的类光约束
void ApplyHamiltonianCorrection(inout vec4 P, float E, KerrGeometry geo) {
    P.w = -E; 
    vec3 p = P.xyz;    

    if (geo.f < 0.0) {
        // f<-1 时，绕原点缩放 p 的二次方程可能无实根（P^t=0 附近退化）。
        // 绕静态观者的动量中心缩放，保持其测得的光线方向和 P_t。
        float OneMinusF = 1.0 - geo.f;
        vec3 Center = (geo.f * E / OneMinusF) * geo.l_up.xyz;
        vec3 SpatialP = p - Center;
        float L_dot_spatial = dot(geo.l_up.xyz, SpatialP);
        float SpatialNormSq = dot(SpatialP, SpatialP) - geo.f * L_dot_spatial * L_dot_spatial;
        if (SpatialNormSq > 0.0) {
            P.xyz = Center + SpatialP * (abs(E) * inversesqrt(OneMinusF * SpatialNormSq));
        }
        return;
    }
    
    float L_dot_p_s = dot(geo.l_up.xyz, p);
    float Pt = P.w; 
    
    float p2 = dot(p, p);
    float Coeff_A = p2 - geo.f * L_dot_p_s * L_dot_p_s;
    float Coeff_B = 2.0 * geo.f * L_dot_p_s * Pt;
    float Coeff_C = -Pt * Pt * (1.0 + geo.f);
    
    float disc = Coeff_B * Coeff_B - 4.0 * Coeff_A * Coeff_C;
    
    if (disc >= 0.0) {
        float sqrtDisc = sqrt(disc);
        float denom = 2.0 * Coeff_A;
        if (abs(denom) > 1e-9) {
            float k1 = (-Coeff_B + sqrtDisc) / denom;
            float k2 = (-Coeff_B - sqrtDisc) / denom;
            float dist1 = abs(k1 - 1.0);
            float dist2 = abs(k2 - 1.0);
            float k = (dist1 < dist2) ? k1 : k2;
            P.xyz *= mix(k, 1.0, clamp(abs(k - 1.0) / 0.1 - 1.0, 0.0, 1.0));
        }
    }
}
//哈密顿量时空导数
State GetDerivativesAnalytic(State S, float PhysicalSpinA, float PhysicalQ2, float fade, bool isOutgoing, inout KerrGeometry geo) {
    State deriv;
    
    ComputeGeometryGradients(S.X.xyz, PhysicalSpinA, PhysicalQ2, fade, geo);
    
    float l_dot_P = dot(geo.l_up.xyz, S.P.xyz) + geo.l_up.w * S.P.w;
    
    vec4 P_flat = vec4(S.P.xyz, -S.P.w); 
    deriv.X = P_flat - geo.f * l_dot_P * geo.l_up;
    
    vec3 grad_A = (-2.0 * geo.r * geo.inv_r2_a2) * geo.inv_r2_a2 * geo.grad_r;
    
    float dirSign = isOutgoing ? -1.0 : 1.0;
    
    // 引入 dirSign 进行导数修正
    float rx_az = dirSign * geo.r * S.X.x - PhysicalSpinA * S.X.z;
    float rz_ax = dirSign * geo.r * S.X.z + PhysicalSpinA * S.X.x;
    
    vec3 d_num_lx = dirSign * S.X.x * geo.grad_r; 
    d_num_lx.x += dirSign * geo.r; 
    d_num_lx.z -= PhysicalSpinA;
    vec3 grad_lx = geo.inv_r2_a2 * d_num_lx + rx_az * grad_A;
    
    vec3 grad_ly = dirSign * (geo.r * geo.inv_den_f) * vec3(-S.X.x * S.X.y, geo.r2 - S.X.y * S.X.y, -S.X.z * S.X.y);
    
    vec3 d_num_lz = dirSign * S.X.z * geo.grad_r;
    d_num_lz.z += dirSign * geo.r;
    d_num_lz.x += PhysicalSpinA;
    vec3 grad_lz = geo.inv_r2_a2 * d_num_lz + rz_ax * grad_A;
    
    vec3 P_dot_grad_l = S.P.x * grad_lx + S.P.y * grad_ly + S.P.z * grad_lz;
    
    vec3 Force = 0.5 * ( (l_dot_P * l_dot_P) * geo.grad_f + (2.0 * geo.f * l_dot_P) * P_dot_grad_l );
    
    deriv.P = vec4(Force, 0.0); 
    
    return deriv;
}

//检测试探步是否穿过奇环面。Rk4里小步的符号需要实时更新不然会被弹飞
float GetIntermediateSign(vec4 StartX, vec4 CurrentX, float CurrentSign, float PhysicalSpinA) {
    if (StartX.y * CurrentX.y < 0.0) {
        float t = StartX.y / (StartX.y - CurrentX.y);
        float rho_cross = length(mix(StartX.xz, CurrentX.xz, t));
        if (rho_cross < abs(PhysicalSpinA)) {
            return -CurrentSign;
        }
    }
    return CurrentSign;
}

//Rk4，第一步复用外部结果
State StepGeodesicRK4_Optimized(
    inout vec4 X, inout vec4 P, 
    float E, float dt, 
    float PhysicalSpinA, float PhysicalQ2, float fade, float r_sign, 
    bool isOutgoing,     
    out KerrGeometry finalGeo, 
    State k1
) {
    State s0; s0.X = X; s0.P = P;
    // k2 Step
    State s1; 
    s1.X = s0.X + 0.5 * dt * k1.X; 
    s1.P = s0.P + 0.5 * dt * k1.P;
    float sign1 = GetIntermediateSign(s0.X, s1.X, r_sign, PhysicalSpinA);
    KerrGeometry geo1;
    ComputeGeometryScalars(s1.X.xyz, PhysicalSpinA, PhysicalQ2, fade, sign1, isOutgoing, geo1);
    State k2 = GetDerivativesAnalytic(s1, PhysicalSpinA, PhysicalQ2, fade, isOutgoing, geo1);
    // k3 Step
    State s2; 
    s2.X = s0.X + 0.5 * dt * k2.X; 
    s2.P = s0.P + 0.5 * dt * k2.P;
    float sign2 = GetIntermediateSign(s0.X, s2.X, r_sign, PhysicalSpinA);
    KerrGeometry geo2;
    ComputeGeometryScalars(s2.X.xyz, PhysicalSpinA, PhysicalQ2, fade, sign2, isOutgoing, geo2);
    State k3 = GetDerivativesAnalytic(s2, PhysicalSpinA, PhysicalQ2, fade, isOutgoing, geo2);
    // k4 Step
    State s3; 
    s3.X = s0.X + dt * k3.X; 
    s3.P = s0.P + dt * k3.P;
    float sign3 = GetIntermediateSign(s0.X, s3.X, r_sign, PhysicalSpinA);
    KerrGeometry geo3;
    ComputeGeometryScalars(s3.X.xyz, PhysicalSpinA, PhysicalQ2, fade, sign3, isOutgoing, geo3);
    State k4 = GetDerivativesAnalytic(s3, PhysicalSpinA, PhysicalQ2, fade, isOutgoing, geo3);
    vec4 finalX = s0.X + (dt / 6.0) * (k1.X + 2.0 * k2.X + 2.0 * k3.X + k4.X);
    vec4 finalP = s0.P + (dt / 6.0) * (k1.P + 2.0 * k2.P + 2.0 * k3.P + k4.P);
    
    float finalSign = GetIntermediateSign(s0.X, finalX, r_sign, PhysicalSpinA);
    ComputeGeometryScalars(finalX.xyz, PhysicalSpinA, PhysicalQ2, fade, finalSign, isOutgoing, finalGeo);
    ApplyHamiltonianCorrection(finalP, E, finalGeo);
    X = finalX;
    P = finalP;
    return k4;
}

// RK4 与三阶嵌入结果的差为四阶量，所以步长反馈使用四次方根。
// 端点导数继续作为下一步 k1；反馈不额外求导，也不重做已完成的积分步。
void StepGeodesicAdaptive(
    inout vec4 X, inout vec4 P, float E, float dt, inout float NextStep,
    float a, float Q2, inout float fade, float r_sign, bool isOutgoing,
    float DistRing, float Tolerance, float FeedbackRadiusSq, float RayBoundary, inout State k1, out KerrGeometry finalGeo
) {
    float PositionScaleSq = max(DistRing * DistRing, 1e-20);
    float MomentumScaleSq = max(dot(P, P), 1e-20);
    vec4 startX = X;
    State k4 = StepGeodesicRK4_Optimized(X, P, E, dt, a, Q2, fade, r_sign, isOutgoing, finalGeo, k1);
    // 端点导数直接使用下一步的 fade，避免过渡区先按旧度规求导再重复刷新。
    float nextFade = CubicInterpolate(clamp(1.0 - (length(X.xyz) - 100.0) / (RayBoundary - 100.0), 0.0, 1.0));
    bool fadeChanged = nextFade != fade;
    if (fadeChanged) {
        fade = nextFade;
        ComputeGeometryScalars(X.xyz, a, Q2, fade, GetIntermediateSign(startX, X, r_sign, a), isOutgoing, finalGeo);
    }
    State Endpoint; Endpoint.X = X; Endpoint.P = P;
    State k5 = GetDerivativesAnalytic(Endpoint, a, Q2, fade, isOutgoing, finalGeo);
    if (fadeChanged || dot(X.xyz, X.xyz) > FeedbackRadiusSq) {
        NextStep = -1.0;
    } else {
        vec4 ErrorX = (dt / 6.0) * (k4.X - k5.X);
        vec4 ErrorP = (dt / 6.0) * (k4.P - k5.P);
        float ErrorSq = max(dot(ErrorX, ErrorX) / PositionScaleSq, dot(ErrorP, ErrorP) / MomentumScaleSq);
        float Factor = clamp(0.9 * sqrt(sqrt(Tolerance * inversesqrt(max(ErrorSq, 1e-30)))), 0.2, 2.0);
        float EndDistRing = length(vec2(length(X.xz) - abs(a), X.y));
        NextStep = abs(dt) * Factor * clamp(EndDistRing / max(DistRing, 1e-10), 0.25, 1.0);
    }
    k1 = k5;
}
// =============================================================================
// SECTION 6: 热折射，吸积盘与喷流,经纬网
// =============================================================================

#define HAZE_STRENGTH           0.2    // 折射强度
#define HAZE_SCALE              5.2     // 噪声频率
#define HAZE_DENSITY_THRESHOLD  0.1     // 密度阈值
#define HAZE_LAYER_THICKNESS    0.8     // 厚度范围倍数
#define HAZE_RADIAL_EXPAND      0.8     // 径向范围倍数
#define HAZE_ROT_SPEED          0.2     // 盘热气旋转速度系数 (相对于开普勒速度)
#define HAZE_FLOW_SPEED         0.15     // 喷流速度系数
#define HAZE_PROBE_STEPS        10      // 试探步数
#define HAZE_STEP_SIZE          0.05    // 每步长度 (Rg)
#define HAZE_DEBUG_MASK         0       // 1 = 显示热气遮罩 Debug
#define HAZE_DEBUG_VECTOR       0       // 1 = 显示力场向量 Debug

#define HAZE_DISK_DENSITY_REF   (iBrightmut * 30.0) 
#define HAZE_JET_DENSITY_REF    (iJetBrightmut * 1.0)


//heat haze基本函数
// heat haze热浪折射，噪声准备
float HazeNoise01(vec3 p) {
    return PerlinNoise(p) * 0.5 + 0.5;
}

// 基础 3D 噪声采样
float GetBaseNoise(vec3 p)
{
    float baseScale = HAZE_SCALE * 0.4; 
    vec3 pos = p * baseScale;
    const mat3 rotNoise = mat3(
         0.80,  0.60,  0.00,
        -0.48,  0.64,  0.60,
        -0.36,  0.48, -0.80
    );
    pos = rotNoise * pos;

    float n1 = HazeNoise01(pos); 
    float n2 = HazeNoise01(pos * 3.0 + vec3(13.5, -2.4, 4.1));

    return n1 * 0.6 + n2 * 0.4; 
}

// 计算吸积盘热浪遮罩
float GetDiskHazeMask(vec3 pos_Rg, float InterRadius, float OuterRadius, float Thin, float Hopper)
{
    float r = length(pos_Rg.xz);
    float y = abs(pos_Rg.y);
    
    float GeometricThin = Thin + max(0.0, (r - 3.0) * Hopper);
    float diskThickRef = GeometricThin; 
    
    float boundaryY = max(0.2, diskThickRef * HAZE_LAYER_THICKNESS);
    
    float vMaskDisk = 1.0 - smoothstep(boundaryY * 0.5, boundaryY * 1.5, y);
    float rMaskDisk = smoothstep(InterRadius * 0.3, InterRadius * 0.8, r) * 
                      (1.0 - smoothstep(OuterRadius * HAZE_RADIAL_EXPAND * 0.75, OuterRadius * HAZE_RADIAL_EXPAND, r));
    
    return vMaskDisk * rMaskDisk;
}

// 计算喷流热浪遮罩
float GetJetHazeMask(vec3 pos_Rg, float InterRadius, float OuterRadius)
{
    float r = length(pos_Rg.xz);
    float y = abs(pos_Rg.y);
    float RhoSq = r * r;

    //核心半径估计 (Jet Core)
    float coreRadiusLimit = sqrt(2.0 * InterRadius * InterRadius + 0.03 * 0.03 * y * y);
    
    //外壳半径估计 (Jet Shell)
    // 对应 JetColor: Rho < 1.3 * InterRadius + 0.25 * Wid
    float shellRadiusLimit = 1.3 * InterRadius + 0.25 * y;
    
    // 取两者较大的作为热浪边界，并稍微膨胀以覆盖辉光
    float maxJetRadius = max(coreRadiusLimit, shellRadiusLimit) * 1.2;
    
    //垂直长度限制
    // 喷流在 OuterRadius 附近开始衰减
    float jLen = OuterRadius * 0.8;
    
    float rMaskJet = 1.0 - smoothstep(maxJetRadius * 0.8, maxJetRadius * 1.1, r);
    float hMaskJet = 1.0 - smoothstep(jLen * 0.75, jLen * 1.0, y);
    
    float startYMask = smoothstep(InterRadius * 0.5, InterRadius * 1.5, y);
    
    return rMaskJet * hMaskJet * startYMask;
}

// 包围盒检测优化
bool IsInHazeBoundingVolume(vec3 pos, float probeDist, float OuterRadius) {
    float maxR = OuterRadius * 1.2;
    float maxY = maxR; 
    float r = length(pos);
    if (r > maxR + probeDist) return false;
    return true;
}

// 同一点与三个有限差分采样共用噪声求值入口。
vec4 HazeNoiseGradient(vec3 position,float eps) {
    vec4 values;
    for(int i=0;i<4;++i) {
        vec3 offset=vec3(0.0);
        if(i>0) offset[i-1]=eps;
        values[i]=GetBaseNoise(position+offset);
    }
    return vec4(values.yzw-values.xxx,values.x);
}

// 计算热浪偏移力
vec3 GetHazeForce(vec3 pos_Rg, float time, float PhysicalSpinA, float PhysicalQ2, 
                  float InterRadius, float OuterRadius, float Thin, float Hopper,
                  float AccretionRate)
{
    //吸积盘热浪强度计算
    float dDens = HAZE_DISK_DENSITY_REF;
    float dLimitAbs = 20.0;
    float dFactorAbs = clamp((log(dDens/dLimitAbs)) / 2.302585, 0.0, 1.0);
    //喷流密度仅作参考
    float jDensRef = HAZE_JET_DENSITY_REF; 
    float dFactorRel = 1.0;
    if (jDensRef > 1e-20) dFactorRel = clamp((log(dDens/jDensRef)) / 2.302585, 0.0, 1.0);
    float diskHazeStrength = dFactorAbs * dFactorRel;

    //喷流热浪强度计算
    float jetHazeStrength = 0.0;
    float JetThreshold = 1e-2;
    
    if (AccretionRate >= JetThreshold)
    {
        float logRate = log(AccretionRate);
        float logMin  = log(JetThreshold);
        float logMax  = log(1.0);
        
        float intensity = clamp((logRate - logMin) / (logMax - logMin), 0.0, 1.0);
        jetHazeStrength = intensity;
    }

    //退出优化
    if (diskHazeStrength <= 0.001 && jetHazeStrength <= 0.001) return vec3(0.0);

    vec3 totalForce = vec3(0.0);
    float eps = 0.1;

    //循环周期计算
    float rotSpeedBase = 100.0 * HAZE_ROT_SPEED; 
    float jetSpeedBase = 50.0 * HAZE_FLOW_SPEED;
    
    // 计算内边缘角速度
    float ReferenceOmega = GetKeplerianAngularVelocity(6.0, 1.0, PhysicalSpinA, PhysicalQ2);
    
    //内圈每旋转一定圈数，噪声完成一次淡入淡出循环
    float AdaptiveFrequency = abs(ReferenceOmega * rotSpeedBase) / (2.0 * kPi * 5.14);
    
    AdaptiveFrequency = max(AdaptiveFrequency, 0.1);

    float flowTime = time * AdaptiveFrequency;
    
    float phase1 = fract(flowTime);
    float phase2 = fract(flowTime + 0.5);
    
    float weight1 = 1.0 - abs(2.0 * phase1 - 1.0);
    float weight2 = 1.0 - abs(2.0 * phase2 - 1.0);
    
    bool doLayer1 = weight1 > 0.05;
    bool doLayer2 = weight2 > 0.05;
    
    float wTotal = (doLayer1 ? weight1 : 0.0) + (doLayer2 ? weight2 : 0.0);
    float w1_norm = (doLayer1 && wTotal > 0.0) ? (weight1 / wTotal) : 0.0;
    float w2_norm = (doLayer2 && wTotal > 0.0) ? (weight2 / wTotal) : 0.0;

    // 时间偏移
    float t_offset1 = phase1 - 0.5;
    float t_offset2 = phase2 - 0.5;

    // 垂直漂移
    float VerticalDrift1 = t_offset1 * 1.0; 
    float VerticalDrift2 = t_offset2 * 1.0;
    
    //吸积盘热浪
    if (diskHazeStrength > 0.001)
    {
        float maskDisk = GetDiskHazeMask(pos_Rg, InterRadius, OuterRadius, Thin, Hopper);
        
        if (maskDisk > 0.001)
        {
            float r_local = length(pos_Rg.xz);
            float omega = GetKeplerianAngularVelocity(r_local, 1.0, PhysicalSpinA, PhysicalQ2);
            
            vec3 gradWorldCombined = vec3(0.0);
            float valCombined = 0.0;

            for(int layer=0;layer<2;++layer) {
                if (!(layer==0?doLayer1:doLayer2)) continue;
                float phaseOffset=layer==0?t_offset1:t_offset2;
                float weight=layer==0?w1_norm:w2_norm;
                float angle=omega*rotSpeedBase*phaseOffset;
                float c=cos(angle), s=sin(angle);
                vec3 pos=pos_Rg;
                pos.x=pos_Rg.x*c-pos_Rg.z*s;
                pos.z=pos_Rg.x*s+pos_Rg.z*c;
                vec4 noise=HazeNoiseGradient(pos,eps);
                vec3 gradWorld;
                gradWorld.x=noise.x*c+noise.z*s;
                gradWorld.y=noise.y;
                gradWorld.z=-noise.x*s+noise.z*c;
                gradWorldCombined+=gradWorld*weight;
                valCombined+=noise.w*weight;
            }

            float cloud = max(0.0, valCombined - HAZE_DENSITY_THRESHOLD);
            cloud /= (1.0 - HAZE_DENSITY_THRESHOLD);
            cloud = pow(cloud, 1.5);
            
            totalForce += gradWorldCombined * maskDisk * cloud * diskHazeStrength;
        }
    }

    //喷流热浪
    if (jetHazeStrength > 0.001)
    {
        float maskJet = GetJetHazeMask(pos_Rg, InterRadius, OuterRadius);
        
        if (maskJet > 0.001)
        {
            float v_jet_mag = 0.9; 
            
            float dist1 = v_jet_mag * jetSpeedBase * t_offset1;
            float dist2 = v_jet_mag * jetSpeedBase * t_offset2;
            
            vec3 gradCombined = vec3(0.0);
            float valCombined = 0.0;
            
            for(int layer=0;layer<2;++layer) {
                if (!(layer==0?doLayer1:doLayer2)) continue;
                vec3 pos=pos_Rg;
                pos.y-=sign(pos_Rg.y)*(layer==0?dist1:dist2);
                vec4 noise=HazeNoiseGradient(pos,eps);
                float weight=layer==0?w1_norm:w2_norm;
                gradCombined+=noise.xyz*weight;
                valCombined+=noise.w*weight;
            }

            float cloud = max(0.0, valCombined - 0.3-0.7*HAZE_DENSITY_THRESHOLD); // 喷流的heat haze相比吸积盘需要更多空隙，不然看着怪
            cloud /= clamp((1.0 - 0.3-0.7*HAZE_DENSITY_THRESHOLD),0.0,1.0);
            cloud = pow(cloud, 1.5);
            
            totalForce += gradCombined * maskJet * cloud * jetHazeStrength;
        }
    }

    return totalForce;
}



vec4 DiskColor(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
               vec4 iP_cov, vec4 lastiP_cov, float iE_obs,
               float InterRadius, float OuterRadius, float Thin, float Hopper, float Brightmut, float Darkmut, float Reddening, float Saturation, float DiskTemperatureArgument,
               float BlackbodyIntensityExponent, float RedShiftColorExponent, float RedShiftIntensityExponent,
               float PeakTemperature, float ShiftMax, 
               float R_Start, float R_End, float PhysicalSpinA, 
               float PhysicalQ2, bool isoutgoing,
               float ThetaInShell,
               inout float RayMarchPhase,
               vec2 WP_CamX, vec2 WP_CamY, inout vec2 StokesQU
               ) 
{
    vec4 CurrentResult = BaseColor;
    //第一次剔除
    float MaxDiskHalfHeight = Thin + max(0.0, Hopper * OuterRadius) + 2.0; 
    if (LastRayPos.y > MaxDiskHalfHeight && RayPos.y > MaxDiskHalfHeight) return BaseColor;//从盘面上下掠过
    if (LastRayPos.y < -MaxDiskHalfHeight && RayPos.y < -MaxDiskHalfHeight) return BaseColor;

    vec2 P0 = LastRayPos.xz;
    vec2 P1 = RayPos.xz;
    vec2 V  = P1 - P0;
    float LenSq = dot(V, V);
    float t_closest = (LenSq > 1e-8) ? clamp(-dot(P0, V) / LenSq, 0.0, 1.0) : 0.0;
    vec2 ClosestPoint = P0 + V * t_closest;
    if (dot(ClosestPoint, ClosestPoint) > (OuterRadius * 1.1) * (OuterRadius * 1.1)) return BaseColor;//与赤道交点过远

    vec3 StartPos = LastRayPos.xyz; 
    vec3 EndPos   = RayPos.xyz;
    vec3 ChordDelta = EndPos - StartPos;
    vec3 ChordDir = length(ChordDelta) > 1e-8 ? normalize(ChordDelta) : vec3(0.0, 1.0, 0.0);
    
    if (max(R_Start, R_End) < InterRadius * 0.9) return BaseColor;

    // --- 利用局域度规计算空间固有距离（Proper Distance） ---
    vec3 MidPos = 0.5 * (StartPos + EndPos);
    KerrGeometry geo_mid;
    // 使用原始输入系下的 Geometry 评估中点度规项
    ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, isoutgoing, geo_mid);
    float l_dot_dx = dot(geo_mid.l_down.xyz, ChordDelta);
    // dl = sqrt( |dx|^2 + f * (l . dx)^2 )
    float proper_dist = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    float StartTimeLag = LastRayPos.w;
    float EndTimeLag   = RayPos.w;



    // 按线段的空间固有长度采样体积
    float TotalDist = proper_dist; 
    float TraveledDist = 0.0;
    
    int SafetyLoopCount = 0;
    const int MaxLoops = 114514; 
    
    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) break;
        SafetyLoopCount++;

        vec3 CurrentPos = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        float DistanceToBlackHole = length(CurrentPos); 
        
        float SmallStepBoundary = max(OuterRadius, 12.0);
        float StepSize = 1.0; 
        //吸积盘的噪声频率越中心越高，这需要子采样步长越中心越小
        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) StepSize *= DistanceToBlackHole;
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary;
        else StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole);
        
        StepSize = max(0.01, StepSize); 

        float DistToNextSample = RayMarchPhase * StepSize;
        float NextTarget = min(TotalDist, TraveledDist + DistToNextSample);

        vec3 PosPrev = CurrentPos;//关于系和插值，一定要先插值后换到ingoing系，因为原始大步所在系的自适应，传入大步曲线一定在原系更接近直线
        vec3 PosNext = mix(StartPos, EndPos, clamp(NextTarget / max(1e-9, TotalDist), 0.0, 1.0));

        bool crossed = (PosPrev.y * PosNext.y < 0.0);
        bool shouldSample = false;
        vec3 SamplePos = PosNext;
        crossed = false;
        //子步进相位通过RayMarchPhase跨大步传递
        //这里是薄盘优化
        if (crossed)
        {
            float t_cross = abs(PosPrev.y) / max(1e-9, abs(PosPrev.y) + abs(PosNext.y));
            vec3 CPoint = mix(PosPrev, PosNext, t_cross);
            
            SamplePos = CPoint + min(Thin, length(CPoint - PosPrev)) * ChordDir * (-1.0 + 2.0 * RandomStep(10000.0 * (CPoint.zx / OuterRadius), fract(iTraceTime * 1.0 + 0.5)));
            shouldSample = true;
            
            RayMarchPhase = 1.0;
            TraveledDist = NextTarget; 
        }
        else
        {
            if (NextTarget < TotalDist)
            {
                SamplePos = PosNext;
                shouldSample = true;
                RayMarchPhase = 1.0;
                TraveledDist = NextTarget;
            }
            else
            {
                float DistanceTraveled = TotalDist - TraveledDist;
                RayMarchPhase -= DistanceTraveled / StepSize;
                if (RayMarchPhase < 0.0) RayMarchPhase = 0.0;
                TraveledDist = TotalDist;
            }
        }

        if (shouldSample)
        {
            float TimeInterpolant = min(1.0, TraveledDist / max(1e-9, TotalDist));
            float CurrentRayTimeLag = mix(StartTimeLag, EndTimeLag, TimeInterpolant);
            //子采样的插值是线性的
            vec4 Sample_X = vec4(SamplePos, CurrentRayTimeLag);
            vec4 Sample_P_cov = mix(lastiP_cov, iP_cov, TimeInterpolant);
            
            if (isoutgoing) {//吸积盘位置定义在ingoing系，插值坐标需要换到ingoing系
                transformKerrSchild_YSpin(Sample_X, 1.0, Sample_P_cov, 0.5, PhysicalSpinA, PhysicalQ2, true);
            }
            
            SamplePos = Sample_X.xyz;
            float EmissionTime = iBlackHoleTime + Sample_X.w;

            float PosR = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            float PosY = SamplePos.y;
            
            float SamplePlanarRadius = length(SamplePos.xz);
            float GeometricThin = Thin + max(0.0, (SamplePlanarRadius - 3.0) * Hopper);//漏斗形状大致轮廓
            float InterCloudEffectiveRadius = (PosR - InterRadius) / min(OuterRadius - InterRadius, 12.0);//内层整体自转云轮廓
            float InnerCloudBound = max(GeometricThin, Thin * 1.0) * max(0.0, 1.0 - 5.0 * pow(InterCloudEffectiveRadius, 2.0));
            float UnionBound = max(GeometricThin * 1.5, max(0.0, InnerCloudBound));//1.5为厚度扰动留余地

            if (abs(PosY) < UnionBound && PosR < OuterRadius && PosR > InterRadius)//再剔除
            {
                 

                 float NoiseLevel = max(0.0, 2.0 - 0.6 * GeometricThin);
                 float x = (PosR - InterRadius) / max(1e-6, OuterRadius - InterRadius);
                 float a_param = max(1.0, (OuterRadius - InterRadius) / 10.0);
                 float EffectiveRadius = (-1.0 + sqrt(max(0.0, 1.0 + 4.0 * a_param * a_param * x - 4.0 * x * a_param))) / (2.0 * a_param - 2.0);
                 if(a_param == 1.0) EffectiveRadius = x;
                 
                 float DenAndThiFactor = Shape(EffectiveRadius, 0.9, 1.5);//这个曲线在漏斗基础上控制形状曲线
                 float ThicknessCap = max(1e-6, GeometricThin * DenAndThiFactor);
                 if (abs(PosY) < max(ThicknessCap, InnerCloudBound)) {
                     KerrGeometry geo_emit;
                     ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, false, geo_emit);
                     vec4 Sample_P_up = RaiseIndex(Sample_P_cov, geo_emit);
                     vec3 local_Dir = normalize(Sample_P_up.xyz);
                     float RotPosR_ForThick = PosR + 0.25 / 3.0 * EmissionTime;
                     float PosLogTheta_ForThick = Vec2ToThetaUnit(SamplePlanarRadius, SamplePos.zx, vec2(cos(-2.0 * log(max(1e-6, PosR))), sin(-2.0 * log(max(1e-6, PosR)))));
                     float ThickNoise = GenerateAccretionDiskNoise(vec3(1.5 * PosLogTheta_ForThick, RotPosR_ForThick, 0.0), -0.7 + NoiseLevel, 1.3 + NoiseLevel, 80.0);//噪声层级是对数增长的
                     float PerturbedThickness = max(1e-6, GeometricThin * DenAndThiFactor * (0.4 + 0.6 * clamp(GeometricThin - 0.5, 0.0, 2.5) / 2.5 + (1.0 - (0.4 + 0.6 * clamp(GeometricThin - 0.5, 0.0, 2.5) / 2.5)) * SoftSaturate(ThickNoise)));//扰动厚度让薄盘好看
                     
                     if ((abs(PosY) < PerturbedThickness) || (abs(PosY) < InnerCloudBound))//再剔除
                     {
                         float AngularVelocity = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ2);//切向始终按照圆轨道角速度
                         //为防止拧紧，这里的处理方式是沿特定螺线下落，但是这在远处退化为径向下落，所以后文在远处叠加了整体自转密度波悬臂，后续可能学se在远处换成分层自转过渡。下面的螺线使得恒定径向速度下切向始终是当地圆轨道速度

                         
                         float inv_r = 1.0 / max(1e-6, PosR);
                         float inv_r2 = inv_r * inv_r;
                         float V_pot = inv_r - (PhysicalQ2) * inv_r2;
                         
                         float g_tt = -(1.0 - V_pot);
                         float g_tphi = -PhysicalSpinA * V_pot; 
                         float g_phiphi = PosR * PosR + PhysicalSpinA * PhysicalSpinA + PhysicalSpinA * PhysicalSpinA * V_pot;
                         float norm_metric = g_tt + 2.0 * AngularVelocity * g_tphi + AngularVelocity * AngularVelocity * g_phiphi;
                         
                         float min_norm = -0.01; 
                         float u_t = inversesqrt(max(abs(min_norm), -norm_metric));
                         
                         float P_phi = - SamplePos.x * Sample_P_cov.z + SamplePos.z * Sample_P_cov.x;
                         float E_emit = u_t * (iE_obs - AngularVelocity * P_phi);
                         float FreqRatio = 1.0 / max(1e-6, E_emit);//对于圆轨道可以解析计算频移
                     
                         float DiskTemperature = pow(DiskTemperatureArgument * pow(1.0 / max(1e-6, PosR), 3.0) * max(1.0 - sqrt(InterRadius / max(1e-6, PosR)), 0.000001), 0.25);//标准薄盘温度
                         float VisionTemperature = DiskTemperature * pow(FreqRatio, RedShiftColorExponent); //黑体谱蓝移还是黑体谱
                         float BrightWithoutRedshift = 0.05 * min(OuterRadius / (1000.0), 1000.0 / OuterRadius) + 0.55 / exp(5.0 * EffectiveRadius) * mix(0.2 + 0.8 * abs(local_Dir.y), 1.0, clamp(GeometricThin - 0.8, 0.2, 1.0)); //对中等厚度盘亮度的修正，额外的温度衰减，减弱薄盘侧视亮度
                         BrightWithoutRedshift *= pow(DiskTemperature / PeakTemperature, BlackbodyIntensityExponent); 
                         
                         float RotPosR = RotPosR_ForThick;
                         float Density = DenAndThiFactor;
                         vec4 SampleColor = vec4(0.0);
                     
                         if (abs(PosY) < PerturbedThickness)
                         {
                         float u = sqrt(max(1e-6, PosR));
                         float k_cubed = PhysicalSpinA * 0.70710678;
                         float SpiralTheta;
                         if (abs(k_cubed) < 0.001 * u * u * u) {
                             float inv_u = 1.0 / u; float eps3 = k_cubed * pow(inv_u, 3.0);
                             SpiralTheta = -16.9705627 * inv_u * (1.0 - 0.25 * eps3 + 0.142857 * eps3 * eps3);
                         } else {
                             float k = sign(k_cubed) * pow(abs(k_cubed), 0.33333333);
                             float logTerm = (PosR - k*u + k*k) / max(1e-9, pow(u+k, 2.0));
                             SpiralTheta = (5.6568542 / k) * (0.5 * log(max(1e-9, logTerm)) + 1.7320508 * (atan(2.0*u - k, 1.7320508 * k) - 1.5707963));
                         }
                         float PosTheta = Vec2ToThetaUnit(SamplePlanarRadius, SamplePos.zx, vec2(cos(-SpiralTheta), sin(-SpiralTheta)));
                         float PosLogarithmicTheta = PosLogTheta_ForThick;
                             float Levelmut = 0.91 * log(1.0 + (0.06 / 0.91 * max(0.0, min(1000.0, PosR) - 10.0)));
                             float Conmut = 80.0 * log(1.0 + (0.1 * 0.06 * max(0.0, min(1000000.0, PosR) - 10.0)));
                             
                             SampleColor = vec4(GenerateAccretionDiskNoise(vec3(0.1 * RotPosR, 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * PosTheta), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 4.0 - Levelmut, 80.0 - Conmut)); //基本的螺线内流云
                             
                             if(PosTheta + kPi < 0.1 * kPi) {//环向缝合
                                 SampleColor *= (PosTheta + kPi) / (0.1 * kPi);
                                 SampleColor += (1.0 - ((PosTheta + kPi) / (0.1 * kPi))) * vec4(GenerateAccretionDiskNoise(vec3(0.1 * RotPosR, 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * (PosTheta + 2.0 * kPi)), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 4.0 - Levelmut, 80.0 - Conmut));
                             }
                             
                             if(PosR > max(0.15379 * OuterRadius, 0.15379 * 64.0)) {//密度波悬臂，整体自转
                                 float TimeShiftedRadiusTerm = PosR * (4.65114e-6) - 0.1 / 3.0 * EmissionTime;
                                 float Spir = (GenerateAccretionDiskNoise(vec3(0.1 * (TimeShiftedRadiusTerm - 0.08 * OuterRadius * PosLogarithmicTheta), 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * PosLogarithmicTheta), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 3.0 - Levelmut, 80.0 - Conmut)); 
                                 if(PosLogarithmicTheta + kPi < 0.1 * kPi) {
                                     Spir *= (PosLogarithmicTheta + kPi) / (0.1 * kPi);
                                     Spir += (1.0 - ((PosLogarithmicTheta + kPi) / (0.1 * kPi))) * (GenerateAccretionDiskNoise(vec3(0.1 * (TimeShiftedRadiusTerm - 0.08 * OuterRadius * (PosLogarithmicTheta + 2.0 * kPi)), 0.1 * PosY, 0.02 * pow(OuterRadius, 0.7) * (PosLogarithmicTheta + 2.0 * kPi)), NoiseLevel + 2.0 - Levelmut, NoiseLevel + 3.0 - Levelmut, 80.0 - Conmut));
                                 }
                                 SampleColor *= (mix(1.0, clamp(0.7 * Spir * 1.5 - 0.5, 0.0, 3.0), 0.5 + 0.5 * max(-1.0, 1.0 - exp(-1.5 * 0.1 * (100.0 * PosR / max(OuterRadius, 64.0) - 20.0)))));
                             }
                     
                             float VerticalMixFactor = max(0.0, (1.0 - abs(PosY) / PerturbedThickness)); //密度向两侧递减
                             Density *= 0.7 * VerticalMixFactor * Density;
                             SampleColor.xyz *= Density * 1.4;
                             SampleColor.a *= (Density) * (Density) / 0.3;
                             
                             float RelHeight = clamp(abs(PosY) / PerturbedThickness, 0.0, 1.0);
                             SampleColor.xyz *= max(0.0, (0.2 + 2.0 * sqrt(max(0.0, RelHeight * RelHeight + 0.001))));//中心加深，表面增亮
                         }
                         //光子环增亮增蓝
                         SampleColor.xyz *= 1.0 + clamp(iPhotonRingBoost, 0.0, 10.0) * clamp(0.3 * ThetaInShell - 0.1, 0.0, 1.0);
                         VisionTemperature *= 1.0 + clamp(iPhotonRingColorTempBoost, 0.0, 10.0) * clamp(0.3 * ThetaInShell - 0.1, 0.0, 1.0);
                         if (abs(PosY) < InnerCloudBound)
                         {
                             //内层整体自转云
                             float InnerAngVel = GetKeplerianAngularVelocity(max(3.0, InterRadius), 1.0, PhysicalSpinA, PhysicalQ2);
                             float InnerCloudTimePhase = max(1e-6, InnerAngVel) * EmissionTime;
                             float DustIntensity = max(1.0 - pow(PosY / (GeometricThin * max(1.0 - 5.0 * pow(InterCloudEffectiveRadius, 2.0), 0.0001)), 2.0), 0.0);
                             if (iInnerCloudFadeRs > 0.0)
                                 DustIntensity *= smoothstep(0.0, max(iInnerCloudFadeRs, 1e-6), PosR - InterRadius);
                             if (DustIntensity > 0.0) {
                                 float DustNoise = InnerCloudNoise(SamplePos.zx, PosR, PosY, InnerCloudTimePhase);
                                 float DustVal = DustIntensity * DustNoise;
                                 SampleColor += 0.02 * vec4(vec3(DustVal), 0.2 * DustVal) * sqrt(max(0.0, 1.0001 - local_Dir.y * local_Dir.y));
                             }
                         }
                     
                         SampleColor.xyz *= BrightWithoutRedshift * KelvinToRgb(VisionTemperature); 
                         SampleColor.xyz *= min(pow(FreqRatio, RedShiftIntensityExponent), ShiftMax); 
                         SampleColor.xyz *= min(1.0, 1.3 * (OuterRadius - PosR) / (OuterRadius - InterRadius)); //内侧增亮
                         SampleColor.a   *= 0.125;
                         
                         // 1. 用局部等效外径计算亮度修正
                         float DilutionOuterRadius = mix(min(OuterRadius, 25.0), OuterRadius, smoothstep(6.0, max(0.05 * OuterRadius, 12.0), PosR));//posr较小时等效外径为25
                         vec4 BoostFactor = max(//很薄的盘增亮      漏斗盘减暗
                            mix(vec4(5.0 / (max(Thin, 0.2) + (0.0 + Hopper * 0.5) * DilutionOuterRadius)), vec4(vec3(0.3 + 0.7 * 5.0 / (Thin + (0.0 + Hopper * 0.5) * DilutionOuterRadius)), 1.0), 0.0),
                                       //厚盘增亮
                            mix(vec4(100.0 / DilutionOuterRadius), vec4(vec3(0.3 + 0.7 * 100.0 / DilutionOuterRadius), 1.0), exp(-pow(20.0 * PosR / DilutionOuterRadius, 2.0)))
                         );
                         SampleColor *= BoostFactor;
                         
                         // 2. 计算内圈增亮参数
                         float InnerBrightenFac = mix(3.0, 2.0, clamp((OuterRadius - 50.0) / 50.0, 0.0, 1.0));
                         float InnerBrightenRatio = 1.0 - clamp(6.0 * (PosR - InterRadius) / (OuterRadius - InterRadius), 0.0, 1.0);
                         InnerBrightenRatio *= InnerBrightenRatio;
                         
                         // 3. 分层应用颜色与透明度的微调 
                         //                                     顶视增亮                 当                             密度低
                         SampleColor.xyz *= mix(1.0, max(1.0, abs(local_Dir.y) / 0.2), clamp(0.3 - 0.6 * (PerturbedThickness / max(1e-6, Density) - 1.0), 0.0, 0.3));
                         //非常薄盘的亮度补偿
                         SampleColor.xyz *= 1.0 + 1.2 * max(0.0, max(0.0, min(1.0, 3.0 - 2.0 * Thin)) * min(0.5, 1.0 - 5.0 * Hopper));
                     
                         SampleColor.xyz *= Brightmut * (1.0 + InnerBrightenFac * InnerBrightenRatio);
                         SampleColor.a   *= Darkmut * (1.0 + (1.0 + InnerBrightenFac) * InnerBrightenRatio);
                         
                         if (E_emit < 0.0) //使用负能判断平行宇宙光子，因此要求盘和喷流在本宇宙严格类时，不然会被误判为平行宇宙，在黑洞模式不显示，最大延拓上反色
                         {
                             float cMax = max(max(SampleColor.r, SampleColor.g), SampleColor.b);
                             float cMin = min(min(SampleColor.r, SampleColor.g), SampleColor.b);
                             SampleColor.rgb = vec3(cMax + cMin) - SampleColor.rgb;
                             if(iWhitehole==0) SampleColor.rgba=vec4(0.0);
                         }
                     
                         vec4 StepColor = SampleColor * StepSize;
                     
                         if (iPolarization != 0) {//计算偏振
                             float chi = -0.7; 
                             float cosChi = cos(chi);
                             float sinChi = sin(chi);
                             
                             vec4 B_tor = vec4(-SamplePos.z, 0.0, SamplePos.x, 0.0);
                             vec4 B_rad = vec4(SamplePos.x, SamplePos.y, SamplePos.z, 0.0);
                             vec4 B_up = normalize(B_tor) * cosChi + normalize(B_rad) * sinChi;
                             B_up.w = 0.0;
                         
                             vec4 u_up_fluid = vec4(AngularVelocity * (-SamplePos.z), 0.0, AngularVelocity * SamplePos.x, 1.0) * u_t;
                         
                             vec4 p_up = Sample_P_up;
                         
                             vec4 f_down;
                             f_down.x =  det3(u_up_fluid.yzw, p_up.yzw, B_up.yzw);
                             f_down.y = -det3(u_up_fluid.xzw, p_up.xzw, B_up.xzw);
                             f_down.z =  det3(u_up_fluid.xyw, p_up.xyw, B_up.xyw);
                             f_down.w = -det3(u_up_fluid.xyz, p_up.xyz, B_up.xyz);
                         
                             float f_norm = sqrt(max(1e-12, abs(dot(RaiseIndex(f_down, geo_emit), f_down))));
                             f_down /= f_norm;
                         
                             vec4 Emit_X = vec4(SamplePos, EmissionTime);
                             vec2 WP_emit = GetWalkerPenrose(Emit_X, Sample_P_cov, f_down, PhysicalSpinA, PhysicalQ2, PosR);
                             
                             vec2 ScreenAmps = SolvePolarization(WP_emit, WP_CamX, WP_CamY);
                             
                             float weight = (SampleColor.r + SampleColor.g + SampleColor.b) * StepSize * pow(1.0 - CurrentResult.a, 1.0);
                             StokesQU.x += (ScreenAmps.x * ScreenAmps.x - ScreenAmps.y * ScreenAmps.y) * weight;
                             StokesQU.y += (2.0 * ScreenAmps.x * ScreenAmps.y) * weight;
                         }
                     
                         float aR = 1.0 + Reddening * (1.0 - 1.0);//红化
                         float aG = 1.0 + Reddening * (3.0 - 1.0);
                         float aB = 1.0 + Reddening * (6.0 - 1.0);
                         
                         float transmission = 1.0 - CurrentResult.a;
                         float weightR = pow(transmission, aR);
                         float weightG = pow(transmission, aG);
                         float weightB = pow(transmission, aB);
                         float Sum_rgb = (StepColor.r + StepColor.g + StepColor.b) * weightG;
                         float Denominator = StepColor.r * weightR + StepColor.g * weightG + StepColor.b * weightB;
                         
                         float r001 = 0.0; float g001 = 0.0; float b001 = 0.0;
                         if (Denominator > 0.000001)//饱和度
                         {
                             r001 = Sum_rgb * StepColor.r * weightR / Denominator;
                             g001 = Sum_rgb * StepColor.g * weightG / Denominator;
                             b001 = Sum_rgb * StepColor.b * weightB / Denominator;
                             
                             r001 *= pow(3.0 * r001 / (r001 + g001 + b001), Saturation);
                             g001 *= pow(3.0 * g001 / (r001 + g001 + b001), Saturation);
                             b001 *= pow(3.0 * b001 / (r001 + g001 + b001), Saturation);
                         }
                         
                         CurrentResult.r += r001;
                         CurrentResult.g += g001;
                         CurrentResult.b += b001;
                         CurrentResult.a += StepColor.a * (1.0 - CurrentResult.a);
                     }
                 }
            }
        }
    }
    return CurrentResult;
}
vec4 DiskColorPhy(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
               vec4 iP_cov, vec4 lastiP_cov, float iE_obs,
               float InterRadius, float OuterRadius, float Thin, float Hopper, float Brightmut, float Darkmut, float Reddening, float Saturation, float DiskTemperatureArgument,
               float BlackbodyIntensityExponent, float RedShiftColorExponent, float RedShiftIntensityExponent,
               float PeakTemperature, float ShiftMax, 
               float PhysicalSpinA, 
               float PhysicalQ2, bool isoutgoing,
               float ThetaInShell,
               inout float RayMarchPhase,
               vec2 WP_CamX, vec2 WP_CamY, inout vec2 StokesQU
               ) 
{
    vec4 CurrentResult = BaseColor;

    float MaxDiskHalfHeight = Thin + max(0.0, Hopper * OuterRadius) + 2.0; 
    if (LastRayPos.y > MaxDiskHalfHeight && RayPos.y > MaxDiskHalfHeight) return BaseColor;
    if (LastRayPos.y < -MaxDiskHalfHeight && RayPos.y < -MaxDiskHalfHeight) return BaseColor;

    vec2 P0 = LastRayPos.xz;
    vec2 P1 = RayPos.xz;
    vec2 V  = P1 - P0;
    float LenSq = dot(V, V);
    float t_closest = (LenSq > 1e-8) ? clamp(-dot(P0, V) / LenSq, 0.0, 1.0) : 0.0;
    vec2 ClosestPoint = P0 + V * t_closest;
    if (dot(ClosestPoint, ClosestPoint) > (OuterRadius * 1.1) * (OuterRadius * 1.1)) return BaseColor;

    vec3 StartPos = LastRayPos.xyz; 
    vec3 EndPos   = RayPos.xyz;
    vec3 ChordDelta = EndPos - StartPos;
    vec3 ChordDir = length(ChordDelta) > 1e-8 ? normalize(ChordDelta) : vec3(0.0, 1.0, 0.0);

    // --- 【同步：利用局域度规计算空间固有距离（Proper Distance）】 ---
    vec3 MidPos = 0.5 * (StartPos + EndPos);
    KerrGeometry geo_mid;
    ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, isoutgoing, geo_mid);
    float l_dot_dx = dot(geo_mid.l_down.xyz, ChordDelta);
    float proper_dist = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    float StartTimeLag = LastRayPos.w;
    float EndTimeLag   = RayPos.w;

    float R_Start = KerrSchildRadius(StartPos, PhysicalSpinA, 1.0);
    float R_End   = KerrSchildRadius(RayPos.xyz, PhysicalSpinA, 1.0);
    if (max(R_Start, R_End) < InterRadius * 0.9) return BaseColor;

    // 按线段的空间固有长度采样体积
    float TotalDist = proper_dist; 
    float TraveledDist = 0.0;
    
    int SafetyLoopCount = 0;
    const int MaxLoops = 114514; 

    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) break;
        SafetyLoopCount++;

        vec3 CurrentPos = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        float DistanceToBlackHole = length(CurrentPos); 
        
        float SmallStepBoundary = max(OuterRadius, 12.0);
        float StepSize = 1.0; 
        
        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) StepSize *= DistanceToBlackHole;
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary;
        else StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole);
        
        StepSize = max(0.01, StepSize); 

        // 同步相位的步进逻辑
        float DistToNextSample = RayMarchPhase * StepSize;
        float NextTarget = min(TotalDist, TraveledDist + DistToNextSample);

        vec3 PosPrev = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        vec3 PosNext = mix(StartPos, EndPos, clamp(NextTarget / max(1e-9, TotalDist), 0.0, 1.0));

        bool crossed = (PosPrev.y * PosNext.y < 0.0);
        bool shouldSample = false;
        vec3 SamplePos = PosNext;
        crossed = false;

        if (crossed)
        {
            float t_cross = abs(PosPrev.y) / max(1e-9, abs(PosPrev.y) + abs(PosNext.y));
            vec3 CPoint = mix(PosPrev, PosNext, t_cross);
            
            SamplePos = CPoint + min(Thin, length(CPoint - PosPrev)) * ChordDir * (-1.0 + 2.0 * RandomStep(10000.0 * (CPoint.zx / OuterRadius), fract(iTraceTime * 1.0 + 0.5)));
            shouldSample = true;
            
            RayMarchPhase = 1.0;
            TraveledDist = NextTarget; 
        }
        else
        {
            if (NextTarget < TotalDist)
            {
                SamplePos = PosNext;
                shouldSample = true;
                RayMarchPhase = 1.0;
                TraveledDist = NextTarget;
            }
            else
            {
                float DistanceTraveled = TotalDist - TraveledDist;
                RayMarchPhase -= DistanceTraveled / StepSize;
                if (RayMarchPhase < 0.0) RayMarchPhase = 0.0;
                TraveledDist = TotalDist;
            }
        }

        if (shouldSample)
        {
            float TimeInterpolant = min(1.0, TraveledDist / max(1e-9, TotalDist));
            float CurrentRayTimeLag = mix(StartTimeLag, EndTimeLag, TimeInterpolant);
            
            // --- 【同步：动量插值与坐标变换】 ---
            vec4 Sample_X = vec4(SamplePos, CurrentRayTimeLag);
            vec4 Sample_P_cov = mix(lastiP_cov, iP_cov, TimeInterpolant);
            
            if (isoutgoing) {
                transformKerrSchild_YSpin(Sample_X, 1.0, Sample_P_cov, 0.5, PhysicalSpinA, PhysicalQ2, true);
            }
            
            SamplePos = Sample_X.xyz;
            float EmissionTime = iBlackHoleTime + Sample_X.w;

            float PosR = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            float PosY = SamplePos.y;
            
            float GeometricThin = length(SamplePos.xz) * Hopper + Thin;
            float UnionBound = (GeometricThin * 1.0);

            if (abs(PosY) < UnionBound && PosR < OuterRadius && PosR > InterRadius)
            {
                 // --- 【同步：局域度规与逆变动量提升】 ---
                 KerrGeometry geo_emit;
                 ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, false, geo_emit);
                 vec4 Sample_P_up = RaiseIndex(Sample_P_cov, geo_emit);

                 float AngularVelocity = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ2);
                 
                 float inv_r = 1.0 / max(1e-6, PosR);
                 float inv_r2 = inv_r * inv_r;
                 
                 float V_pot = inv_r - (PhysicalQ2) * inv_r2;
                 
                 float g_tt = -(1.0 - V_pot);
                 float g_tphi = -PhysicalSpinA * V_pot; 
                 float g_phiphi = PosR * PosR + PhysicalSpinA * PhysicalSpinA + PhysicalSpinA * PhysicalSpinA * V_pot;
                 
                 float norm_metric = g_tt + 2.0 * AngularVelocity * g_tphi + AngularVelocity * AngularVelocity * g_phiphi;
                 
                 float min_norm = -0.01; 
                 float u_t = inversesqrt(max(abs(min_norm), -norm_metric));
                 
                 // --- 【同步：角动量计算使用插值后的 Sample_P_cov】 ---
                 float P_phi = - SamplePos.x * Sample_P_cov.z + SamplePos.z * Sample_P_cov.x;
                 
                 float E_emit = u_t * (iE_obs - AngularVelocity * P_phi);
                 float FreqRatio = 1.0 / max(1e-6, E_emit);
                 if(E_emit < 0.0) FreqRatio = 0.0;

                 float DiskTemperature = pow(DiskTemperatureArgument * pow(1.0 / max(1e-6, PosR), 3.0) * max(1.0 - sqrt(InterRadius / max(1e-6, PosR)), 0.000001), 0.25);
                 float VisionTemperature = DiskTemperature * pow(FreqRatio, RedShiftColorExponent); 
                 float BrightWithoutRedshift = 1.0;
                 BrightWithoutRedshift *= pow(DiskTemperature / PeakTemperature, BlackbodyIntensityExponent); 
                 
                 float Density = 1.0;
                 vec4 SampleColor = vec4(0.0);

                 SampleColor.xyz = vec3(BrightWithoutRedshift);
                 SampleColor.a = Density;

                 SampleColor.xyz *= KelvinToRgb(VisionTemperature); 
                 SampleColor.xyz *= pow(FreqRatio, RedShiftIntensityExponent); 

                 SampleColor.xyz *= Brightmut;
                 SampleColor.a   *= Darkmut;

                 SampleColor.xyz *= pow(InterRadius / 1.0, 4.0);

                 bool IsPositiveEnergy = iE_obs > 0.0;
                 if (!IsPositiveEnergy) 
                 {
                     float cMax = max(max(SampleColor.r, SampleColor.g), SampleColor.b);
                     float cMin = min(min(SampleColor.r, SampleColor.g), SampleColor.b);
                     SampleColor.rgb = vec3(cMax + cMin) - SampleColor.rgb;
                     if(iWhitehole==0) SampleColor.rgba=vec4(0.0);
                 }

                 vec4 StepColor = SampleColor * StepSize;

                 // =========================================================
                 // 偏振计算
                 // =========================================================
                 if (iPolarization != 0) {
                     float chi = -0.7; 
                     float cosChi = cos(chi);
                     float sinChi = sin(chi);
                     
                     vec4 B_tor = vec4(-SamplePos.z, 0.0, SamplePos.x, 0.0);
                     vec4 B_rad = vec4(SamplePos.x, SamplePos.y, SamplePos.z, 0.0);
                     vec4 B_up = normalize(B_tor) * cosChi + normalize(B_rad) * sinChi;
                     B_up.w = 0.0;
                 
                     vec4 u_up_fluid = vec4(AngularVelocity * (-SamplePos.z), 0.0, AngularVelocity * SamplePos.x, 1.0) * u_t;
                 
                     // --- 【同步：使用插值并计算出的 Sample_P_up】 ---
                     vec4 p_up = Sample_P_up;
                 
                     vec4 f_down;
                     f_down.x =  det3(u_up_fluid.yzw, p_up.yzw, B_up.yzw);
                     f_down.y = -det3(u_up_fluid.xzw, p_up.xzw, B_up.xzw);
                     f_down.z =  det3(u_up_fluid.xyw, p_up.xyw, B_up.xyw);
                     f_down.w = -det3(u_up_fluid.xyz, p_up.xyz, B_up.xyz);
                 
                     float f_norm = sqrt(max(1e-12, abs(dot(RaiseIndex(f_down, geo_emit), f_down))));
                     f_down /= f_norm;
                 
                     // --- 【同步：传入插值后的 Sample_P_cov】 ---
                     vec4 Emit_X = vec4(SamplePos, EmissionTime);
                     vec2 WP_emit = GetWalkerPenrose(Emit_X, Sample_P_cov, f_down, PhysicalSpinA, PhysicalQ2, PosR);
                     
                     vec2 ScreenAmps = SolvePolarization(WP_emit, WP_CamX, WP_CamY);
                     
                     float weight = (SampleColor.r + SampleColor.g + SampleColor.b) * StepSize * pow(1.0 - CurrentResult.a, 1.0);
                     StokesQU.x += (ScreenAmps.x * ScreenAmps.x - ScreenAmps.y * ScreenAmps.y) * weight;
                     StokesQU.y += (2.0 * ScreenAmps.x * ScreenAmps.y) * weight;
                 }
                 // =========================================================

                 // 简化的颜色叠加逻辑
                 CurrentResult = CurrentResult + StepColor * pow((1.0 - CurrentResult.a), 1.0);
            }
        }
    }
    
    return CurrentResult;
}

vec4 DiskColortoRed(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
               vec4 iP_cov, vec4 lastiP_cov, float iE_obs,
               float InterRadius, float OuterRadius, float Thin, float Hopper, float Brightmut, float Darkmut, float Reddening, float Saturation, float DiskTemperatureArgument,
               float BlackbodyIntensityExponent, float RedShiftColorExponent, float RedShiftIntensityExponent,
               float PeakTemperature, float ShiftMax, 
               float PhysicalSpinA, 
               float PhysicalQ2, bool isoutgoing,
               float ThetaInShell,
               inout float RayMarchPhase,
               vec2 WP_CamX, vec2 WP_CamY, inout vec2 StokesQU
               ) 
{
    vec4 CurrentResult = BaseColor;

    float MaxDiskHalfHeight = Thin + max(0.0, Hopper * OuterRadius) + 2.0; 
    if (LastRayPos.y > MaxDiskHalfHeight && RayPos.y > MaxDiskHalfHeight) return BaseColor;
    if (LastRayPos.y < -MaxDiskHalfHeight && RayPos.y < -MaxDiskHalfHeight) return BaseColor;

    vec2 P0 = LastRayPos.xz;
    vec2 P1 = RayPos.xz;
    vec2 V  = P1 - P0;
    float LenSq = dot(V, V);
    float t_closest = (LenSq > 1e-8) ? clamp(-dot(P0, V) / LenSq, 0.0, 1.0) : 0.0;
    vec2 ClosestPoint = P0 + V * t_closest;
    if (dot(ClosestPoint, ClosestPoint) > (OuterRadius * 1.1) * (OuterRadius * 1.1)) return BaseColor;

    vec3 StartPos = LastRayPos.xyz; 
    vec3 EndPos   = RayPos.xyz;
    vec3 ChordDelta = EndPos - StartPos;
    vec3 ChordDir = length(ChordDelta) > 1e-8 ? normalize(ChordDelta) : vec3(0.0, 1.0, 0.0);

    // --- 【同步：利用局域度规计算空间固有距离（Proper Distance）】 ---
    vec3 MidPos = 0.5 * (StartPos + EndPos);
    KerrGeometry geo_mid;
    ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, isoutgoing, geo_mid);
    float l_dot_dx = dot(geo_mid.l_down.xyz, ChordDelta);
    float proper_dist = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    float StartTimeLag = LastRayPos.w;
    float EndTimeLag   = RayPos.w;

    float R_Start = KerrSchildRadius(StartPos, PhysicalSpinA, 1.0);
    float R_End   = KerrSchildRadius(RayPos.xyz, PhysicalSpinA, 1.0);
    if (max(R_Start, R_End) < InterRadius * 0.9) return BaseColor;

    // 按线段的空间固有长度采样体积
    float TotalDist = proper_dist; 
    float TraveledDist = 0.0;
    
    int SafetyLoopCount = 0;
    const int MaxLoops = 114514; 

    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) break;
        SafetyLoopCount++;

        vec3 CurrentPos = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        float DistanceToBlackHole = length(CurrentPos); 
        
        float SmallStepBoundary = max(OuterRadius, 12.0);
        float StepSize = 1.0; 
        
        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) StepSize *= DistanceToBlackHole;
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary;
        else StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole);
        
        StepSize = max(0.01, StepSize); 

        // 同步相位的步进逻辑
        float DistToNextSample = RayMarchPhase * StepSize;
        float NextTarget = min(TotalDist, TraveledDist + DistToNextSample);

        vec3 PosPrev = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        vec3 PosNext = mix(StartPos, EndPos, clamp(NextTarget / max(1e-9, TotalDist), 0.0, 1.0));

        bool crossed = (PosPrev.y * PosNext.y < 0.0);
        bool shouldSample = false;
        vec3 SamplePos = PosNext;
        crossed = false;

        if (crossed)
        {
            float t_cross = abs(PosPrev.y) / max(1e-9, abs(PosPrev.y) + abs(PosNext.y));
            vec3 CPoint = mix(PosPrev, PosNext, t_cross);
            
            SamplePos = CPoint + min(Thin, length(CPoint - PosPrev)) * ChordDir * (-1.0 + 2.0 * RandomStep(10000.0 * (CPoint.zx / OuterRadius), fract(iTraceTime * 1.0 + 0.5)));
            shouldSample = true;
            
            RayMarchPhase = 1.0;
            TraveledDist = NextTarget; 
        }
        else
        {
            if (NextTarget < TotalDist)
            {
                SamplePos = PosNext;
                shouldSample = true;
                RayMarchPhase = 1.0;
                TraveledDist = NextTarget;
            }
            else
            {
                float DistanceTraveled = TotalDist - TraveledDist;
                RayMarchPhase -= DistanceTraveled / StepSize;
                if (RayMarchPhase < 0.0) RayMarchPhase = 0.0;
                TraveledDist = TotalDist;
            }
        }

        if (shouldSample)
        {
            float TimeInterpolant = min(1.0, TraveledDist / max(1e-9, TotalDist));
            float CurrentRayTimeLag = mix(StartTimeLag, EndTimeLag, TimeInterpolant);
            
            // --- 【同步：动量插值与坐标变换】 ---
            vec4 Sample_X = vec4(SamplePos, CurrentRayTimeLag);
            vec4 Sample_P_cov = mix(lastiP_cov, iP_cov, TimeInterpolant);
            
            if (isoutgoing) {
                transformKerrSchild_YSpin(Sample_X, 1.0, Sample_P_cov, 0.5, PhysicalSpinA, PhysicalQ2, true);
            }
            
            SamplePos = Sample_X.xyz;
            float EmissionTime = iBlackHoleTime + Sample_X.w;

            float PosR = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            float PosY = SamplePos.y;
            
            float GeometricThin = length(SamplePos.xz) * Hopper + Thin;
            float UnionBound = (GeometricThin * 1.0);

            if (abs(PosY) < UnionBound && PosR < OuterRadius && PosR > InterRadius)
            {
                 // --- 【同步：局域度规与逆变动量提升】 ---
                 KerrGeometry geo_emit;
                 ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, false, geo_emit);
                 vec4 Sample_P_up = RaiseIndex(Sample_P_cov, geo_emit);

                 float AngularVelocity = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ2);
                 
                 float inv_r = 1.0 / max(1e-6, PosR);
                 float inv_r2 = inv_r * inv_r;
                 
                 float V_pot = inv_r - (PhysicalQ2) * inv_r2;
                 
                 float g_tt = -(1.0 - V_pot);
                 float g_tphi = -PhysicalSpinA * V_pot; 
                 float g_phiphi = PosR * PosR + PhysicalSpinA * PhysicalSpinA + PhysicalSpinA * PhysicalSpinA * V_pot;
                 
                 float norm_metric = g_tt + 2.0 * AngularVelocity * g_tphi + AngularVelocity * AngularVelocity * g_phiphi;
                 
                 float min_norm = -0.01; 
                 float u_t = inversesqrt(max(abs(min_norm), -norm_metric));
                 
                 // --- 【同步：角动量计算使用插值后的 Sample_P_cov】 ---
                 float P_phi = - SamplePos.x * Sample_P_cov.z + SamplePos.z * Sample_P_cov.x;
                 
                 float E_emit = u_t * (iE_obs - AngularVelocity * P_phi);
                 float FreqRatio = 1.0 / max(1e-6, E_emit);
                 if(E_emit < 0.0) FreqRatio = 0.0;

                 float DiskTemperature = pow(DiskTemperatureArgument * pow(1.0 / max(1e-6, PosR), 3.0) * max(1.0 - sqrt(InterRadius / max(1e-6, PosR)), 0.000001), 0.25);
                 float VisionTemperature = DiskTemperature * pow(FreqRatio, RedShiftColorExponent); 
                 float BrightWithoutRedshift = 1.0;
                 BrightWithoutRedshift *= pow(DiskTemperature / PeakTemperature, BlackbodyIntensityExponent); 
                 
                 float Density = 1.0;
                 vec4 SampleColor = vec4(0.0);

                 SampleColor.xyz = vec3(BrightWithoutRedshift);
                 SampleColor.a = Density;

                 // 纯红盘特征
                 SampleColor.xyz *= vec3(1.0, 0.0, 0.0); 
                 SampleColor.xyz *= pow(FreqRatio, RedShiftIntensityExponent); 

                 SampleColor.xyz *= Brightmut;
                 SampleColor.a   *= Darkmut;

                 SampleColor.xyz *= pow(InterRadius / 1.0, 4.0);

                 bool IsPositiveEnergy = iE_obs > 0.0;
                 if (!IsPositiveEnergy) 
                 {
                     float cMax = max(max(SampleColor.r, SampleColor.g), SampleColor.b);
                     float cMin = min(min(SampleColor.r, SampleColor.g), SampleColor.b);
                     SampleColor.rgb = vec3(cMax + cMin) - SampleColor.rgb;
                 }

                 vec4 StepColor = SampleColor * StepSize;

                 // =========================================================
                 // 偏振计算
                 // =========================================================
                 if (iPolarization != 0) {
                     float chi = -0.7; 
                     float cosChi = cos(chi);
                     float sinChi = sin(chi);
                     
                     vec4 B_tor = vec4(-SamplePos.z, 0.0, SamplePos.x, 0.0);
                     vec4 B_rad = vec4(SamplePos.x, SamplePos.y, SamplePos.z, 0.0);
                     vec4 B_up = normalize(B_tor) * cosChi + normalize(B_rad) * sinChi;
                     B_up.w = 0.0;
                 
                     vec4 u_up_fluid = vec4(AngularVelocity * (-SamplePos.z), 0.0, AngularVelocity * SamplePos.x, 1.0) * u_t;
                 
                     // --- 【同步：使用插值并计算出的 Sample_P_up】 ---
                     vec4 p_up = Sample_P_up;
                 
                     vec4 f_down;
                     f_down.x =  det3(u_up_fluid.yzw, p_up.yzw, B_up.yzw);
                     f_down.y = -det3(u_up_fluid.xzw, p_up.xzw, B_up.xzw);
                     f_down.z =  det3(u_up_fluid.xyw, p_up.xyw, B_up.xyw);
                     f_down.w = -det3(u_up_fluid.xyz, p_up.xyz, B_up.xyz);
                 
                     float f_norm = sqrt(max(1e-12, abs(dot(RaiseIndex(f_down, geo_emit), f_down))));
                     f_down /= f_norm;
                 
                     // --- 【同步：传入插值后的 Sample_P_cov】 ---
                     vec4 Emit_X = vec4(SamplePos, EmissionTime);
                     vec2 WP_emit = GetWalkerPenrose(Emit_X, Sample_P_cov, f_down, PhysicalSpinA, PhysicalQ2, PosR);
                     
                     vec2 ScreenAmps = SolvePolarization(WP_emit, WP_CamX, WP_CamY);
                     
                     float weight = (SampleColor.r + SampleColor.g + SampleColor.b) * StepSize * pow(1.0 - CurrentResult.a, 1.0);
                     StokesQU.x += (ScreenAmps.x * ScreenAmps.x - ScreenAmps.y * ScreenAmps.y) * weight;
                     StokesQU.y += (2.0 * ScreenAmps.x * ScreenAmps.y) * weight;
                 }
                 // =========================================================

                 // 简化的颜色叠加逻辑
                 CurrentResult = CurrentResult + StepColor * pow((1.0 - CurrentResult.a), 1.0);
            }
        }
    }
    
    return CurrentResult;
}

vec4 DiskColortoBlue(vec4 BaseColor, float StepLength, vec4 RayPos, vec4 LastRayPos,
               vec3 RayDir, vec3 LastRayDir,vec4 iP_cov, float iE_obs,
               float InterRadius, float OuterRadius, float Thin, float Hopper, float Brightmut, float Darkmut, float Reddening, float Saturation, float DiskTemperatureArgument,
               float BlackbodyIntensityExponent, float RedShiftColorExponent, float RedShiftIntensityExponent,
               float PeakTemperature, float ShiftMax, 
               float PhysicalSpinA, 
               float PhysicalQ2, bool isoutgoing,
               float ThetaInShell,
               inout float RayMarchPhase 
               ) 
{
    vec4 CurrentResult = BaseColor;
    

    float MaxDiskHalfHeight = Thin + max(0.0, Hopper * OuterRadius) + 2.0; 
    if (LastRayPos.y > MaxDiskHalfHeight && RayPos.y > MaxDiskHalfHeight) return BaseColor;
    if (LastRayPos.y < -MaxDiskHalfHeight && RayPos.y < -MaxDiskHalfHeight) return BaseColor;

    vec2 P0 = LastRayPos.xz;
    vec2 P1 = RayPos.xz;
    vec2 V  = P1 - P0;
    float LenSq = dot(V, V);
    float t_closest = (LenSq > 1e-8) ? clamp(-dot(P0, V) / LenSq, 0.0, 1.0) : 0.0;
    vec2 ClosestPoint = P0 + V * t_closest;
    if (dot(ClosestPoint, ClosestPoint) > (OuterRadius * 1.1) * (OuterRadius * 1.1)) return BaseColor;

    vec3 StartPos = LastRayPos.xyz; 
    vec3 DirVec   = RayDir; 
    float StartTimeLag = LastRayPos.w;
    float EndTimeLag   = RayPos.w;

    float R_Start = KerrSchildRadius(StartPos, PhysicalSpinA, 1.0);
    float R_End   = KerrSchildRadius(RayPos.xyz, PhysicalSpinA, 1.0);
    if (max(R_Start, R_End) < InterRadius * 0.9) return BaseColor;

    
    float TotalDist = StepLength;
    float TraveledDist = 0.0;
    
    int SafetyLoopCount = 0;
    const int MaxLoops = 114514; 

    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) break;
        SafetyLoopCount++;

        vec3 CurrentPos = StartPos + DirVec * TraveledDist;
        float DistanceToBlackHole = length(CurrentPos); 
        
        // 计算局部密度
        float SmallStepBoundary = max(OuterRadius, 12.0);
        float StepSize = 1.0; 
        
        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) StepSize *= DistanceToBlackHole;
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary;
        else StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole);
        
        StepSize = max(0.01, StepSize); 

        //  相位与距离计算
        float DistToNextSample = RayMarchPhase * StepSize;
        float DistRemainingInRK4 = TotalDist - TraveledDist;

        if (DistToNextSample > DistRemainingInRK4)
        {
            // 情况 A：下一个采样点超出了当前的 RK4 步长范围
            // 我们走完这段剩余距离，但不进行采样
            // 并更新相位，表示我们已经走了一部分路程
            
            float PhaseProgress = DistRemainingInRK4 / StepSize;
            RayMarchPhase -= PhaseProgress; // 消耗相位
            
            // 确保相位数值稳定
            if(RayMarchPhase < 0.0) RayMarchPhase = 0.0; // 理论不应发生，除非精度误差
            
            TraveledDist = TotalDist; // 结束本段积分
            break;
        }

        float dt = DistToNextSample;
        
        // 移动到采样点
        TraveledDist += dt;
        vec3 SamplePos = StartPos + DirVec * TraveledDist;
        
        float TimeInterpolant = min(1.0, TraveledDist / max(1e-9, TotalDist));
        float CurrentRayTimeLag = mix(StartTimeLag, EndTimeLag, TimeInterpolant);
        float EmissionTime = iBlackHoleTime + CurrentRayTimeLag;

        // 薄盘优化
        vec3 PreviousPos = CurrentPos; // 这一步的起点
        //if(PreviousPos.y * SamplePos.y < 0.0)
        //{
        //
        //    vec3 CPoint=(-SamplePos*PreviousPos.y+PreviousPos*SamplePos.y)/(SamplePos.y-PreviousPos.y);
        //    SamplePos=CPoint+min(Thin,length(CPoint-PreviousPos))*DirVec*(-1.0+2.0*RandomStep(10000.0*(SamplePos.zx/OuterRadius), fract(iTraceTime * 1.0 + 0.5)));
        //    
        //
        //}
        float PosR = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
        float PosY = SamplePos.y;
        
        float GeometricThin = length(SamplePos.xz) * Hopper+Thin;
        
        // 计算内侧云参数与包围盒
        float InterCloudEffectiveRadius = (PosR - InterRadius) / min(OuterRadius - InterRadius, 12.0);
        float InnerCloudBound = max(GeometricThin, Thin * 1.0) * max(0.0,1.0 - 5.0 * pow(InterCloudEffectiveRadius, 2.0));
        
        // 外层包围盒取主盘与内侧云的并集
        // GeometricThin * 1.5 是主盘噪声的包围盒，InnerCloudBound 是内侧云的包围盒
        float UnionBound = (GeometricThin * 1.0);

        if (abs(PosY) < UnionBound && PosR < OuterRadius && PosR > InterRadius)
        {


             {
                 float AngularVelocity = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ2);
                 
                 float u = sqrt(max(1e-6, PosR));
                 float k_cubed = PhysicalSpinA * 0.70710678;
                 float SpiralTheta;
                 if (abs(k_cubed) < 0.001 * u * u * u) {
                     float inv_u = 1.0 / u; float eps3 = k_cubed * pow(inv_u, 3.0);
                     SpiralTheta = -16.9705627 * inv_u * (1.0 - 0.25 * eps3 + 0.142857 * eps3 * eps3);
                 } else {
                     float k = sign(k_cubed) * pow(abs(k_cubed), 0.33333333);
                     float logTerm = (PosR - k*u + k*k) / max(1e-9, pow(u+k, 2.0));
                     SpiralTheta = (5.6568542 / k) * (0.5 * log(max(1e-9, logTerm)) + 1.7320508 * (atan(2.0*u - k, 1.7320508 * k) - 1.5707963));
                 }
                 float PosTheta = Vec2ToTheta(SamplePos.zx, vec2(cos(-SpiralTheta), sin(-SpiralTheta)));
                 float PosLogarithmicTheta = Vec2ToTheta(SamplePos.zx, vec2(cos(-2.0 * log(max(1e-6, PosR))), sin(-2.0 * log(max(1e-6, PosR)))));
                 
                 
                 //vec3 FluidVel = AngularVelocity * vec3(SamplePos.z, 0.0, -SamplePos.x);
                 //vec4 U_fluid_unnorm = vec4(FluidVel, 1.0); 
                 //KerrGeometry geo_sample;
                 //ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, geo_sample);
                 //vec4 U_fluid_lower = LowerIndex(U_fluid_unnorm, geo_sample);
                 //float norm_sq = dot(U_fluid_unnorm, U_fluid_lower);
                 //vec4 U_fluid = U_fluid_unnorm * inversesqrt(max(1e-6, abs(norm_sq)));
                 //float E_emit = -dot(iP_cov, U_fluid);
                 //float FreqRatio =  1.0/ max(1e-6, E_emit);
                 

                 // 解析法计算红移
                 float inv_r = 1.0 / max(1e-6, PosR);
                 float inv_r2 = inv_r * inv_r;
                 
                 // 无量纲势能项 (M=0.5 -> 2M=1.0)
                 float V_pot = inv_r - (PhysicalQ2) * inv_r2;
                 
                 // 赤道面度规分量 g_uv
                 float g_tt = -(1.0 - V_pot);
                 float g_tphi = -PhysicalSpinA * V_pot; 
                 float g_phiphi = PosR * PosR + PhysicalSpinA * PhysicalSpinA + PhysicalSpinA * PhysicalSpinA * V_pot;
                 
                 // 归一化条件 U.U = -1 => norm * (u^t)^2 = -1
                 float norm_metric = g_tt + 2.0 * AngularVelocity * g_tphi + AngularVelocity * AngularVelocity * g_phiphi;
                 
                 // 防止超光速区域 (norm >= 0) 导致崩溃
                 float min_norm = -0.01; 
                 float u_t = inversesqrt(max(abs(min_norm), -norm_metric));
                 
                 // 计算角动量 P_phi = x*P_z - z*P_x (这里符号要反一下)
                 float P_phi = - SamplePos.x * iP_cov.z + SamplePos.z * iP_cov.x;
                 
                 // 计算发射能量 E_emit = -u^mu P_mu = u^t * (iE_obs - Omega * P_phi)
                 // 注：iE_obs 即为传入的守恒能量 E_conserved
                 float E_emit = u_t * (iE_obs - AngularVelocity * P_phi);
                 float FreqRatio = 1.0 / max(1e-6, E_emit);
                 // 解析法计算红移结束
                 if(E_emit<0.0) FreqRatio =  0.0;




                 float DiskTemperature = pow(DiskTemperatureArgument * pow(1.0 / max(1e-6, PosR), 3.0) * max(1.0 - sqrt(InterRadius / max(1e-6, PosR)), 0.000001), 0.25);
                 float VisionTemperature = DiskTemperature * pow(FreqRatio, RedShiftColorExponent); 
                 float BrightWithoutRedshift = 1.0;
                 BrightWithoutRedshift *= pow(DiskTemperature / PeakTemperature, BlackbodyIntensityExponent); 
                 
                 float RotPosR = PosR + 0.25 / 3.0 * EmissionTime;
                 float Density = 1.0;
                 
                 vec4 SampleColor = vec4(0.0);

                 

                     SampleColor.xyz =vec3(BrightWithoutRedshift) ;
                     SampleColor.a=Density;
    
                 SampleColor.xyz *= vec3(0.0,0.0,1.0); 
                 SampleColor.xyz *= pow(FreqRatio, RedShiftIntensityExponent); 
                 

                 

                  SampleColor.xyz *= Brightmut;
                  SampleColor.a   *= Darkmut;

                  SampleColor.xyz*=pow(InterRadius/1.0,4.0);

                 bool IsPositiveEnergy =iE_obs>0.0;
                 if (!IsPositiveEnergy) 
                 {
                     float cMax = max(max(SampleColor.r, SampleColor.g), SampleColor.b);
                     float cMin = min(min(SampleColor.r, SampleColor.g), SampleColor.b);
                     SampleColor.rgb = vec3(cMax + cMin) - SampleColor.rgb;
                 }





                 vec4 StepColor = SampleColor * StepSize;
                 

                 CurrentResult = CurrentResult + StepColor * pow((1.0 - CurrentResult.a), 1.0);

            }
        }
        RayMarchPhase = 1.0;
    }
    
    return CurrentResult;
}

vec4 JetColor(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
              vec4 iP_cov, vec4 lastiP_cov, float iE_obs,
              float InterRadius, float OuterRadius, float JetRedShiftIntensityExponent, float JetBrightmut, float JetReddening, float JetSaturation, float AccretionRate, float JetShiftMax, 
              float PhysicalSpinA, 
              float PhysicalQ2, bool isoutgoing,
              inout float RayMarchPhase 
              ) 
{
    vec4 CurrentResult = BaseColor;
    vec3 StartPos = LastRayPos.xyz; 
    vec3 EndPos   = RayPos.xyz;
    
    if (any(isnan(StartPos)) || any(isinf(StartPos))) return BaseColor;

    // --- 1. 计算局域度规并提取固有空间距离 ---
    vec3 ChordDelta = EndPos - StartPos;
    vec3 MidPos = 0.5 * (StartPos + EndPos);
    KerrGeometry geo_mid;
    ComputeGeometryScalars(MidPos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, isoutgoing, geo_mid);
    
    float l_dot_dx = dot(geo_mid.l_down.xyz, ChordDelta);
    float proper_dist = sqrt(max(1e-9, dot(ChordDelta, ChordDelta) + geo_mid.f * l_dot_dx * l_dot_dx));

    float StartTimeLag = LastRayPos.w;
    float EndTimeLag   = RayPos.w;

    float TotalDist = proper_dist; // 线段的空间固有长度
    float TraveledDist = 0.0;
    
    float R_Start = length(StartPos.xz);
    float R_End   = length(RayPos.xz); 
    float MaxR_XZ = max(R_Start, R_End);
    float MaxY    = max(abs(StartPos.y), abs(RayPos.y));
    
    if (MaxR_XZ > OuterRadius * 1.5 && MaxY < OuterRadius) return BaseColor;

    int SafetyLoopCount = 0;
    const int MaxLoops = 114514; 
    
    while (TraveledDist < TotalDist && SafetyLoopCount < MaxLoops)
    {
        if (CurrentResult.a > 0.99) break;
        SafetyLoopCount++;

        // 利用插值比例计算当前检查点位置
        vec3 CurrentPos = mix(StartPos, EndPos, clamp(TraveledDist / max(1e-9, TotalDist), 0.0, 1.0));
        float DistanceToBlackHole = length(CurrentPos); 
        
        float SmallStepBoundary = max(OuterRadius, 12.0);
        float StepSize = 1.0; 
        
        StepSize *= 0.15 + 0.25 * min(max(0.0, 0.5 * (0.5 * DistanceToBlackHole / max(10.0 , SmallStepBoundary) - 1.0)), 1.0);
        if ((DistanceToBlackHole) >= 2.0 * SmallStepBoundary) StepSize *= DistanceToBlackHole;
        else if ((DistanceToBlackHole) >= 1.0 * SmallStepBoundary) StepSize *= ((1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0)) * (2.0 * SmallStepBoundary - DistanceToBlackHole) + DistanceToBlackHole * (DistanceToBlackHole - SmallStepBoundary)) / SmallStepBoundary;
        else StepSize *= min(1.0 + 0.25 * max(DistanceToBlackHole - 12.0, 0.0), DistanceToBlackHole);
        
        StepSize = max(0.01, StepSize); 

        float DistToNextSample = RayMarchPhase * StepSize;
        float NextTarget = min(TotalDist, TraveledDist + DistToNextSample);

        bool shouldSample = false;
        if (NextTarget < TotalDist)
        {
            shouldSample = true;
            RayMarchPhase = 1.0;
            TraveledDist = NextTarget;
        }
        else
        {
            float DistanceTraveled = TotalDist - TraveledDist;
            RayMarchPhase -= DistanceTraveled / StepSize;
            if(RayMarchPhase < 0.0) RayMarchPhase = 0.0;
            TraveledDist = TotalDist;
        }

        if (shouldSample)
        {
            // --- 2. 在原始坐标系下进行物理量插值 ---
            float TimeInterpolant = min(1.0, TraveledDist / max(1e-9, TotalDist));
            vec3 OrigSamplePos = mix(StartPos, EndPos, TimeInterpolant);
            float CurrentRayTimeLag = mix(StartTimeLag, EndTimeLag, TimeInterpolant);
            
            vec4 Sample_X = vec4(OrigSamplePos, CurrentRayTimeLag);
            vec4 Sample_P_cov = mix(lastiP_cov, iP_cov, TimeInterpolant);

            // --- 3. 统一转换到 Ingoing 坐标系 ---
            if (isoutgoing) {
                transformKerrSchild_YSpin(Sample_X, 1.0, Sample_P_cov, 0.5, PhysicalSpinA, PhysicalQ2, true);
            }
            
            vec3 SamplePos = Sample_X.xyz;
            float EmissionTime = iBlackHoleTime + Sample_X.w;

            float PosR = KerrSchildRadius(SamplePos, PhysicalSpinA, 1.0);
            float PosY = SamplePos.y;
            float RhoSq = dot(SamplePos.xz, SamplePos.xz);
            float Rho = sqrt(RhoSq);
            
            vec4 AccumColor = vec4(0.0);
            bool InJet = false;

            //// 内部喷流核心
            //if (RhoSq < 2.0 * InterRadius * InterRadius + 0.03 * 0.03 * PosY * PosY && PosR < sqrt(2.0) * OuterRadius)
            //{
            //    InJet = true;
            //    float ShapeVal = 1.0 / sqrt(max(1e-9, InterRadius * InterRadius + 0.02 * 0.02 * PosY * PosY));
            //    float noiseInput = 0.3 * (EmissionTime - 1.0 / 0.8 * abs(abs(PosY) + 100.0 * (RhoSq / max(0.1, PosR)))) / max(1e-6, (OuterRadius / 100.0)) / (1.0 / 0.8);
            //    float a = mix(0.7 + 0.3 * PerlinNoise1D(noiseInput), 1.0, exp(-0.01 * 0.01 * PosY * PosY));
            //    
            //    vec4 Col = vec4(1.0, 1.0, 1.0, 0.5) * max(0.0, 1.0 - 5.0 * ShapeVal * abs(1.0 - pow(Rho * ShapeVal, 2.0))) * ShapeVal;
            //    Col *= a;
            //    Col *= max(0.0, 1.0 - 1.0 * exp(-0.0001 * PosY / max(1e-6, InterRadius) * PosY / max(1e-6, InterRadius)));
            //    Col *= exp(-4.0 / (2.0) * PosR / max(1e-6, OuterRadius) * PosR / max(1e-6, OuterRadius));
            //    Col *= 0.5;
            //    
            //    AccumColor += Col * StepSize; 
            //}
            //
            // 外围扭转喷流壳
            float Wid = abs(PosY);
            if (Rho < 1.3 * InterRadius + 0.25 * Wid && Rho > 0.7 * InterRadius + 0.15 * Wid && PosR < 30.0 * InterRadius)
            {
                InJet = true;
                float InnerTheta = 2.0 * GetKeplerianAngularVelocity(InterRadius, 1.0, PhysicalSpinA, PhysicalQ2) * (EmissionTime - 1.0 / 0.8 * abs(PosY));
                float ShapeVal = 1.0 / max(1e-9, (InterRadius + 0.2 * Wid));
                
                float Twist = 0.2 * (1.1 - exp(-0.1 * 0.1 * PosY * PosY)) * (PerlinNoise1D(0.35 * (EmissionTime - 1.0 / 0.8 * abs(PosY)) / (1.0 / 0.8)) - 0.5);
                vec2 TwistedPos = SamplePos.xz + Twist * vec2(cos(0.666666 * InnerTheta), -sin(0.666666 * InnerTheta));
                
                vec4 Col = vec4(1.0, 1.0, 1.0, 0.5) * max(0.0, 1.0 - 2.0 * abs(1.0 - pow(length(TwistedPos) * ShapeVal, 2.0))) * ShapeVal;
                Col *= 1.0 - exp(-PosY / max(1e-6, InterRadius) * PosY / max(1e-6, InterRadius));
                Col *= exp(-0.005 * PosY / max(1e-6, InterRadius) * PosY / max(1e-6, InterRadius));
                Col *= 0.5;
                
                AccumColor += Col * StepSize; 
            }

            if (InJet)
            {
                // --- 4. 使用转换到 Ingoing 系后的物理计算 ---
                KerrGeometry geo_sample;
                // 注意：isoutgoing 必须填 false，因为我们已经在上文将其统一转换为了 Ingoing 坐标
                ComputeGeometryScalars(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, 1.0, false, geo_sample);
                
                // 物理喷流速度 0.8c, 洛伦兹因子 Gamma = 1/sqrt(1 - 0.8^2) = 1.6666667
                float v_jet = 0.8;
                float Gamma = 1.6666667; 
                vec3 U_spatial = vec3(0.0, sign(PosY) * Gamma * v_jet, 0.0);
                
                // 根据归一化条件 g_uv U^u U^v = -1 求解时间分量 U^t
                float l_dot_u_sp = dot(geo_sample.l_down.xyz, U_spatial);
                float U_sp_sq = dot(U_spatial, U_spatial);
                
                float A = -1.0 + geo_sample.f;
                float B = 2.0 * geo_sample.f * l_dot_u_sp;
                float C = U_sp_sq + geo_sample.f * l_dot_u_sp * l_dot_u_sp + 1.0; 
                
                float Det = B * B - 4.0 * A * C;
                
                // 光锥约束保护
                if (Det < 0.0) {
                    if (A < 0.0) {
                        U_spatial *= 0.5; 
                    } else {
                        ComputeGeometryGradients(SamplePos, PhysicalSpinA, PhysicalQ2, 1.0, geo_sample);
                        U_spatial = -1.5 * geo_sample.grad_r; 
                    }
                    l_dot_u_sp = dot(geo_sample.l_down.xyz, U_spatial);
                    U_sp_sq = dot(U_spatial, U_spatial);
                    C = U_sp_sq + geo_sample.f * l_dot_u_sp * l_dot_u_sp + 1.0;
                    B = 2.0 * geo_sample.f * l_dot_u_sp;
                    Det = max(0.0, B * B - 4.0 * A * C);
                }
                
                float sqrtDet = sqrt(Det);
                float Ut;
                if (abs(A) < 1e-7) {
                    Ut = -C / max(1e-19, B); 
                } else {
                    if (B < 0.0) {
                         Ut = 2.0 * C / (-B + sqrtDet);
                    } else {
                         Ut = (-B - sqrtDet) / (2.0 * A);
                    }
                }
                
                vec4 U_jet = vec4(U_spatial, Ut);
                
                // 严谨计算红移/蓝移 E = - p_u U^u
                // 使用刚刚插值并经过了换系处理的局域四动量 Sample_P_cov
                float E_emit = -dot(Sample_P_cov, U_jet);
                float FreqRatio = 1.0 / max(1e-6, E_emit);

                float JetTemperature = min(100000.0 * FreqRatio,100000.0); 
                AccumColor.xyz *= KelvinToRgb(JetTemperature);
                AccumColor.xyz *= min(pow(FreqRatio, JetRedShiftIntensityExponent), JetShiftMax);
                AccumColor *= JetBrightmut * (0.5 + 0.5 * tanh(log(max(1e-6, AccretionRate)) + 1.0));
                AccumColor.a *= 0.0; 
                
                bool IsPositiveEnergy = E_emit > 0.0;
                if (!IsPositiveEnergy) 
                {
                    float cMax = max(max(AccumColor.r, AccumColor.g), AccumColor.b);
                    float cMin = min(min(AccumColor.r, AccumColor.g), AccumColor.b);
                    AccumColor.rgb = vec3(cMax + cMin) - AccumColor.rgb;
                }

                // ... (颜色累加不变)
                float aR = 1.0 + JetReddening * (1.0 - 1.0);
                float aG = 1.0 + JetReddening * (3.0 - 1.0);
                float aB = 1.0 + JetReddening * (6.0 - 1.0);
                float transmission = 1.0 - CurrentResult.a;
                float weightR = pow(transmission, aR);
                float weightG = pow(transmission, aG);
                float weightB = pow(transmission, aB);
                float Sum_rgb = (AccumColor.r + AccumColor.g + AccumColor.b) * weightG;
                
                float Denominator = AccumColor.r * weightR + AccumColor.g * weightG + AccumColor.b * weightB;
                float r001 = 0.0; float g001 = 0.0; float b001 = 0.0;
                if (Denominator > 0.000001)
                {
                    r001 = Sum_rgb * AccumColor.r * weightR / Denominator;
                    g001 = Sum_rgb * AccumColor.g * weightG / Denominator;
                    b001 = Sum_rgb * AccumColor.b * weightB / Denominator;
                    
                    r001 *= pow(3.0 * r001 / (r001 + g001 + b001), JetSaturation);
                    g001 *= pow(3.0 * g001 / (r001 + g001 + b001), JetSaturation);
                    b001 *= pow(3.0 * b001 / (r001 + g001 + b001), JetSaturation);
                }
                
                CurrentResult.r += r001;
                CurrentResult.g += g001;
                CurrentResult.b += b001;
                CurrentResult.a += AccumColor.a * (1.0 - CurrentResult.a);
            }
        }
    }
    return CurrentResult;
}

vec4 ImageDiskColor(sampler2D diskTexture, vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
                    vec4 P_cov, vec4 LastP_cov, 
                    float PhysicalSpinA, float PhysicalQ2, bool isoutgoing,
                    float EndStepSign, float dlambda,
                    float InterRadius, float OuterRadius,
                    float RedShiftColorExponent, float RedShiftIntensityExponent)
{
    vec4 CurrentResult = BaseColor;
    // 如果不透明度已满，直接返回
    if (CurrentResult.a > 0.99) return CurrentResult;

    // 仅当光线穿过赤道面 (y=0) 时触发运算
    if (LastRayPos.y * RayPos.y >= 0.0) return CurrentResult;

    float StartStepSign = EndStepSign;
    float t_cross = -1.0;
    vec4 DiskHitX = vec4(0.0);
    vec3 DiskHitPos = vec3(0.0);

    // 获取起点和终点的几何信息并升指标，求出坐标对仿射参量的导数 dX/dlambda
    KerrGeometry geo_last;
    ComputeGeometryScalars(LastRayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, StartStepSign, isoutgoing, geo_last);
    vec4 V0 = RaiseIndex(LastP_cov, geo_last); 
    vec4 T0 = V0 * dlambda; 

    KerrGeometry geo_curr;
    ComputeGeometryScalars(RayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, EndStepSign, isoutgoing, geo_curr);
    vec4 V1 = RaiseIndex(P_cov, geo_curr);     
    vec4 T1 = V1 * dlambda; 

    // --- 赤道盘相交：三次 Hermite 曲线求根 ---
    float denom = (LastRayPos.y - RayPos.y);
    if(abs(denom) > 1e-9) {
        t_cross = LastRayPos.y / denom; // 线性初猜
        
        // 牛顿迭代求精确零点
        for(int iter = 0; iter < 3; iter++) {
            float t2 = t_cross * t_cross;
            float t3 = t2 * t_cross;
            
            float h00 = 2.0*t3 - 3.0*t2 + 1.0;
            float h10 = t3 - 2.0*t2 + t_cross;
            float h01 = -2.0*t3 + 3.0*t2;
            float h11 = t3 - t2;
            float yt = h00*LastRayPos.y + h10*T0.y + h01*RayPos.y + h11*T1.y;
            
            float dh00 = 6.0*t2 - 6.0*t_cross;
            float dh10 = 3.0*t2 - 4.0*t_cross + 1.0;
            float dh01 = -6.0*t2 + 6.0*t_cross;
            float dh11 = 3.0*t2 - 2.0*t_cross;
            float dyt = dh00*LastRayPos.y + dh10*T0.y + dh01*RayPos.y + dh11*T1.y;
            
            t_cross -= yt / (dyt + 1e-12);
        }
        t_cross = clamp(t_cross, 0.0, 1.0);
        
        // 依据精确 t 计算交点四维坐标
        float t2 = t_cross * t_cross;
        float t3 = t2 * t_cross;
        vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t_cross, -2.0*t3 + 3.0*t2, t3 - t2);
        DiskHitX = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
        DiskHitPos = DiskHitX.xyz;
        
        if (length(DiskHitPos.xz) < abs(PhysicalSpinA)) {
            StartStepSign = -EndStepSign;
        }
    } else {
        return CurrentResult;
    }

    // --- 将坐标映射回统一的 Ingoing 参考系 ---
       // --- 将坐标映射回统一的 Ingoing 参考系 ---
    float HitTime_disk = DiskHitX.w;
    vec3 PatternPosDisk = DiskHitPos;
    if (isoutgoing) {
        vec4 tempX = vec4(DiskHitPos, HitTime_disk);
        vec4 dummyP = vec4(0.0);
        float diskSign = (length(DiskHitPos.xz) < abs(PhysicalSpinA)) ? -StartStepSign : StartStepSign;
        transformKerrSchild_YSpin(tempX, diskSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
        PatternPosDisk = tempX.xyz;
        HitTime_disk = tempX.w; // 顺手补上时间的更新，保证光线时间滞后计算精确
    }

    // --- 几何与纹理映射逻辑 ---
    float r_xz = length(PatternPosDisk.xz);
    // 挖去内部孔洞
    if (r_xz < InterRadius) return CurrentResult;

    // 计算旋转角并对坐标进行矩阵旋转
    float EmissionTime = iBlackHoleTime + HitTime_disk; // 提取光线命中该位置时的物理世界时间
    float rotAngle = iImageRotationSpeed * EmissionTime; // <- 注意：请确保名字与你传入的 uniform 变量名一致
    float cosA = cos(rotAngle);
    float sinA = sin(rotAngle);
    
    // 对坐标进行反向矩阵旋转（等效于图片本身正向旋转）
    vec2 RotatedXZ = mat2(cosA, sinA, -sinA, cosA) * PatternPosDisk.xz;

    // 根据对角线为 OuterRadius 计算正方形边长
    // 对角线 D = OuterRadius，正方形边长 S = D / sqrt(2)
    float ImageWidth = OuterRadius * 0.70710678; 
    float HalfWidth = ImageWidth * 0.5;

    // 剔除正方形边界之外的区域 (改用旋转后的 RotatedXZ)
    if (abs(RotatedXZ.x) > HalfWidth || abs(RotatedXZ.y) > HalfWidth) return CurrentResult;

    // 映射到 [0, 1] 的 UV 坐标 (改用旋转后的 RotatedXZ)
    float U = (RotatedXZ.x + HalfWidth) / ImageWidth;
    float V = (RotatedXZ.y + HalfWidth) / ImageWidth;

    // 使用 textureLod 避免由于控制流分支导致计算 mipmap 梯度报错
    vec4 TexColor = textureLod(diskTexture, vec2(U, V), 0.0);
    TexColor.xyz*=iBrightmut; 
    TexColor.a*=iDarkmut;   
    if (TexColor.a < 0.01) return CurrentResult; // 纯透明部分跳过

    // --- 提取四维动量用于频移计算 ---
    vec4 HitP_cov = mix(LastP_cov, P_cov, t_cross);

    // 计算静止物体 (U_spatial = 0) 局部能量 E_emit
    // 计算带有圆轨道速度（开普勒运动）的局部能量 E_emit
    KerrGeometry geo_hit;
    float hitSign = (length(DiskHitPos.xz) < abs(PhysicalSpinA)) ? -StartStepSign : StartStepSign;
    ComputeGeometryScalars(DiskHitPos, PhysicalSpinA, PhysicalQ2, 1.0, hitSign, isoutgoing, geo_hit);

    // 获取当前交点的等效半径，并算出对应的开普勒角速度（内部有限制防止在半径极小处崩溃）
    float PosR = KerrSchildRadius(DiskHitPos, PhysicalSpinA, hitSign);
    float AngularVelocity = GetKeplerianAngularVelocity(max(InterRadius, PosR), 1.0, PhysicalSpinA, PhysicalQ2);
    
    // 构造带圆轨道旋转的未归一化四维速度，自旋方向为Y轴 (v_x = -Omega * z, v_z = Omega * x)
    vec4 U_unnorm = vec4(AngularVelocity * DiskHitPos.z, 0.0, -AngularVelocity * DiskHitPos.x, 1.0);

    vec4 U_lower = LowerIndex(U_unnorm, geo_hit);
    float norm_sq = dot(U_unnorm, U_lower);
    float norm = sqrt(max(1e-9, abs(norm_sq))); // 取绝对值并加上容差避免极端超光速情况下的崩溃
    vec4 U_orbit = U_unnorm / norm;

    // 发射能量 = - P_mu * U^mu
    float E_emit = -dot(HitP_cov, U_orbit); 
    float Shift = 1.0 / max(1e-6, abs(E_emit));

    // --- 非黑体天空盒风格频移逻辑 ---
    float EffectiveColorShift = pow(Shift, RedShiftColorExponent);

    vec3 Rcolor = TexColor.r * 1.0 * WavelengthToRgb(max(453.0, 645.0 / EffectiveColorShift));
    vec3 Gcolor = TexColor.g * 1.5 * WavelengthToRgb(max(416.0, 510.0 / EffectiveColorShift));
    vec3 Bcolor = TexColor.b * 0.6 * WavelengthToRgb(max(380.0, 440.0 / EffectiveColorShift));
    vec3 Scolor = Rcolor + Gcolor + Bcolor;

    float OStrength = 0.3 * TexColor.r + 0.6 * TexColor.g + 0.1 * TexColor.b;
    float RStrength = 0.3 * Scolor.r + 0.6 * Scolor.g + 0.1 * Scolor.b;
    Scolor *= OStrength / max(RStrength, 0.001);

    // 亮度频移乘数
    Scolor *= pow(Shift, RedShiftIntensityExponent);

    if (E_emit < 0.0) {
        float cMax = max(max(Scolor.r, Scolor.g), Scolor.b);
        float cMin = min(min(Scolor.r, Scolor.g), Scolor.b);
        Scolor.rgb = vec3(cMax + cMin) - Scolor.rgb;
        if (iWhitehole == 0) {
            Scolor.rgb = vec3(0.0);
            TexColor.a = 0.0;
        }
    }

    // 混合到当前累计颜色
    CurrentResult.rgb += Scolor * TexColor.a * (1.0 - CurrentResult.a);
    CurrentResult.a   += TexColor.a * (1.0 - CurrentResult.a);

    return CurrentResult;
}
// 三阶分形布朗运动，逐层加入域扭曲，形成流动的表面纹理。
float Fbm_Standalone(vec3 x) {
    vec2 sum = vec2(0.0);
    float ampl = 1.0;
    for (int i = 0; i < 3; ++i) {
        sum += ampl * PerlinNoise(x);
        // 域扭曲让相邻噪声层沿不同方向流动。
        x += 1.4 * sum.xyx * vec3(0.7, 0.6, 1.3);
        ampl *= 0.74;
        x *= vec3(4.0, 4.0, 4.0);
    }
    return sum.x;
}
vec4 DensestarColor(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
                    vec4 P_cov, vec4 LastP_cov, 
                    float PhysicalSpinA, float PhysicalQ2, bool isoutgoing,
                    float EndStepSign, float dlambda)
{
    vec4 CurrentResult = BaseColor;
    // 如果不透明度已满，或者未启用致密星渲染，则直接返回
    if (iDensestarsurfaceR == 0.0) return CurrentResult;

    // 获取起点和终点的几何信息并升指标，求出坐标对仿射参量的导数 dX/dlambda
    KerrGeometry geo_last;
    ComputeGeometryScalars(LastRayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, EndStepSign, isoutgoing, geo_last);
    vec4 V0 = RaiseIndex(LastP_cov, geo_last); 
    vec4 T0 = V0 * dlambda; 

    KerrGeometry geo_curr;
    ComputeGeometryScalars(RayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, EndStepSign, isoutgoing, geo_curr);
    vec4 V1 = RaiseIndex(P_cov, geo_curr);     
    vec4 T1 = V1 * dlambda; 

    float TargetSignedR = iDensestarsurfaceR; 
    float TargetGeoR = abs(TargetSignedR); 
    
    vec3 O = LastRayPos.xyz;
    vec3 D_vec = RayPos.xyz - LastRayPos.xyz;

    // 椭球面求交
    vec2 roots = IntersectKerrEllipsoid(O, D_vec, TargetGeoR, PhysicalSpinA);
    
    float t_hits[2];
    t_hits[0] = roots.x;
    t_hits[1] = roots.y;
    // 确保按射线前进方向排序
    if (t_hits[0] > t_hits[1]) {
        float temp = t_hits[0]; t_hits[0] = t_hits[1]; t_hits[1] = temp;
    }
    
    for (int j = 0; j < 2; j++) {
        float t = t_hits[j];
        
        if (t >= 0.0 && t <= 1.0) {
            float HitPointSign = EndStepSign;
            if (HitPointSign * TargetSignedR < 0.0) continue;

            // 曲线与椭球面相交的牛顿迭代修整
            for(int iter = 0; iter < 2; iter++) {
                float t2 = t*t; float t3 = t2*t;
                vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
                vec3 pos = (H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1).xyz;
                float curR = KerrSchildRadius(pos, PhysicalSpinA, HitPointSign);
                
                float dt = 0.001;
                float nt = t + dt;
                float nt2 = nt*nt; float nt3 = nt2*nt;
                vec4 nH = vec4(2.0*nt3 - 3.0*nt2 + 1.0, nt3 - 2.0*nt2 + nt, -2.0*nt3 + 3.0*nt2, nt3 - nt2);
                vec3 npos = (nH.x*LastRayPos + nH.y*T0 + nH.z*RayPos + nH.w*T1).xyz;
                float nextR = KerrSchildRadius(npos, PhysicalSpinA, HitPointSign);
                
                float dr_dt = (nextR - curR) / dt;
                t -= (curR - TargetSignedR) / (dr_dt + 1e-12);
            }
            
            if (t < 0.0 || t > 1.0) continue; 
            
            // 提取高精度四维坐标与动量
            float t2 = t*t; float t3 = t2*t;
            vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
            vec4 HitX = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
            
            vec3 HitPos = HitX.xyz;
            float HitTime = HitX.w;
            
            float CheckR = KerrSchildRadius(HitPos, PhysicalSpinA, HitPointSign);
            if (abs(CheckR - TargetSignedR) > 0.1 * TargetGeoR + 0.1) continue; 

            vec4 HitP_cov = mix(LastP_cov, P_cov, t);

            // 映射参考系以提取局部坐标
            vec3 PatternPos = HitPos;
            float PatternTime = HitTime;
            if (isoutgoing) {
                vec4 tempX = vec4(HitPos, HitTime);
                vec4 dummyP = vec4(0.0);
                transformKerrSchild_YSpin(tempX, HitPointSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
                PatternPos = tempX.xyz;
                PatternTime = tempX.w;
            }

            // --- 刚体角速度与四维速度 ---
            float R2 = TargetSignedR * TargetSignedR;
            float a2 = PhysicalSpinA * PhysicalSpinA;
            float Omega_star = PhysicalSpinA / (R2 + a2); // 星体指定等角速度刚体旋转

            float EmissionTime = iBlackHoleTime + PatternTime;
            
            
            // 1. 获取归一化的表面坐标
            vec3 pos_tex = normalize(PatternPos);
            
            // 2. 将 3D 坐标随刚体自旋绕 Y 轴旋转
            float rotAngle = Omega_star * EmissionTime;
            float c_rot = cos(rotAngle);
            float s_rot = sin(rotAngle);
            pos_tex.xz = mat2(c_rot, s_rot, -s_rot, c_rot) * pos_tex.xz;
            
            // 3. 应用中子星的纹理缩放倍数
            pos_tex *= 4.0;
            
            // 4. 用发射时刻驱动表面等离子体流动。
            // 控制流动速度，避免纹理在恒星表面滑动得过快。
            float animSpeed = EmissionTime * 0.01; 
            
            vec3 noisePos = vec3(
                pos_tex.x + sin(animSpeed) * 2.0,
                pos_tex.y + cos(animSpeed) * 2.0, 
                pos_tex.z
            );
            
            // 5. 采样 3D FBM 噪声
            float noiseVal = Fbm_Standalone(noisePos);
            
            // 6. 将噪声映射为温度调制系数，形成表面温度起伏
            float tempMod = clamp(noiseVal * 0.2 + 0.8,0.5,1.5);
            
            // 7. 映射到发光体的物理静止系温度 (基准温度乘以调制系数)
            // 6000 K 是表面温度基准，再由噪声调制。
            float BaseTemp_Kelvin = 6000.0 * tempMod; 
            
            // =================================================================

            // --- 频移系数 g 计算 ---
            // 星体刚体旋转的局部四维速度 U_star
            vec3 VelSpatial = Omega_star * vec3(HitPos.z, 0.0, -HitPos.x);
            vec4 U_star_unnorm = vec4(VelSpatial, 1.0); 
            
            KerrGeometry geo_hit;
            ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ2, 1.0, HitPointSign, isoutgoing, geo_hit);
            vec4 U_star_lower = LowerIndex(U_star_unnorm, geo_hit);
            float norm_sq = dot(U_star_unnorm, U_star_lower);
            vec4 U_star = U_star_unnorm / sqrt(max(1e-9, abs(norm_sq)));

            // 发射能量与无穷远观测能量 (P_cov 的 w 分量为 -E_obs 守恒量)
            float E_emit_raw = -dot(HitP_cov, U_star);
            float g = 1.0 / max(1e-9, abs(E_emit_raw)); 


            // --- 计算频移后的温度与亮度 ---
            // 观测温度 = 静止温度 * (g ^ 频移温度指数)
            float ObsTemp_Kelvin = BaseTemp_Kelvin * pow(g, iDensestarRedShiftColorExponent);
            
            // 获取对应色温的黑体颜色
            vec3 BlackBodyColor = KelvinToRgb(ObsTemp_Kelvin);

            // 观测亮度 = (自身静止温度导致的热辐射亮度基数) * (g ^ 频移亮度指数)
            float BaseIntensity = pow(BaseTemp_Kelvin / 6000.0, iDensestarBlackbodyIntensityExponent); 
            float RedshiftIntensity = pow(g, iDensestarRedShiftIntensityExponent);
            float FinalIntensity = BaseIntensity * RedshiftIntensity;
            // =================================================================
            // ↓↓↓ 测试/调试功能：八卦限颜色与经纬网棋盘格 (取消外部块注释即可生效) ↓↓↓
            if(iDEBUG==5)
            {
                // 获取归一化的随动局部坐标（因为上文 pos_tex 被 *= 4.0 放大过，需还原方向）
                vec3 unit_pos = normalize(pos_tex);
                
                // 1. 八卦限颜色：利用 step 判断 x, y, z 的正负号映射到 RGB
                vec3 octantColor = step(0.0, unit_pos); 
                // 为了避免纯黑(0,0,0)卦限看不见，将其映射到 0.2 ~ 1.0 范围
                octantColor = octantColor * 0.8 + 0.2;  

                // 2. 获取球坐标经纬度
// 2. 获取球坐标经纬度（包含针对 atan(0,0) 和 asin(>1) 的防 NaN 保护）
            float phi = atan(unit_pos.z, abs(unit_pos.x) < 1e-9 && abs(unit_pos.z) < 1e-9 ? 1e-9 : unit_pos.x); 
            float theta = asin(clamp(unit_pos.y, -1.0, 1.0));
                
                // 3. 计算棋盘格网格 (调节 6.0 这个系数可改变网格密度)
                float u = phi * 6.0;   
                float v = theta * 6.0; 
                float checker = mod(floor(u) + floor(v), 2.0); // 结果为 0.0 或 1.0
                
                // 4. 将棋盘格映射为亮度调节系数（例如暗格亮度 0.3，亮格亮度 1.0）
                float checkerIntensity = clamp(checker * 0.7 + 0.3,0.0,1.0);
                
                // 5. 用象限颜色和棋盘格亮度检查透镜与频移
                BlackBodyColor = octantColor;
                FinalIntensity = checkerIntensity * RedshiftIntensity;
            }
            
            // ↑↑↑ 测试/调试功能结束 ↑↑↑
            // =================================================================
            vec4 StarCol = vec4(iDensestarBrightmut * BlackBodyColor * FinalIntensity, 1.0);
            
            // 处理负能量光线 / 反宇宙反色
            if (E_emit_raw < 0.0) {
                float cMax = max(max(StarCol.r, StarCol.g), StarCol.b);
                float cMin = min(min(StarCol.r, StarCol.g), StarCol.b);
                StarCol.rgb = vec3(cMax + cMin) - StarCol.rgb;
                if (iWhitehole == 0) StarCol.rgba = vec4(0.0);
            }
            
            // 将实体完全覆盖上去并退出循环
            CurrentResult.rgb += StarCol.rgb * StarCol.a * (1.0 - CurrentResult.a);
            CurrentResult.a   += StarCol.a * (1.0 - CurrentResult.a);
            
            if(CurrentResult.a > 0.99) break; 
        }
    }

    return CurrentResult;
}

// 网格使用归一化椭球求交，避免小步长或小内视界被绝对阈值跳过。
vec2 IntersectGridEllipsoid(vec3 O, vec3 D, float r, float a)
{
    float InvEquatorialR = inversesqrt(r * r + a * a);
    vec3 Scale = vec3(InvEquatorialR, 1.0 / abs(r), InvEquatorialR);
    vec3 ScaledO = O * Scale;
    vec3 ScaledD = D * Scale;
    float A = dot(ScaledD, ScaledD);
    float B = dot(ScaledO, ScaledD);
    float C = dot(ScaledO, ScaledO) - 1.0;
    if (A <= 0.0) return vec2(-1.0);

    float Discriminant = B * B - A * C;
    if (Discriminant < 0.0) return vec2(-1.0);
    float Q = -B - (B >= 0.0 ? 1.0 : -1.0) * sqrt(Discriminant);
    if (Q == 0.0) return vec2(-B / A);

    vec2 Roots = vec2(Q / A, C / Q);
    return vec2(min(Roots.x, Roots.y), max(Roots.x, Roots.y));
}

// k^r 与 E - Omega_H L 的相对符号区分两支
bool IsIngoingHorizonGridRay(vec4 HitX, vec4 HitP_cov, KerrGeometry geo,
                            float HorizonR, float a, bool isoutgoing,
                            out float HorizonEnergy)
{
    vec4 P_up = RaiseIndex(HitP_cov, geo);
    float OmegaH = a / (HorizonR * HorizonR + a * a);
    float Ly = HitX.z * HitP_cov.x - HitX.x * HitP_cov.z;
    HorizonEnergy = -HitP_cov.w - OmegaH * Ly;
    vec3 Normal = vec3(HitX.x / (geo.r2 + a * a), HitX.y / geo.r2,
                       HitX.z / (geo.r2 + a * a));
    float RadialMomentum = geo.r * dot(Normal, P_up.xyz);
    // 零能量或切向的临界点没有严格的符号分类，沿用当前可表示的正则支。
    if (RadialMomentum == 0.0 || HorizonEnergy == 0.0) return !isoutgoing;
    return (RadialMomentum < 0.0) != (HorizonEnergy < 0.0);
}

// 显示约定：Ingoing 支为未来/深色，Outgoing 支为过去/浅色；平行宇宙反色。
vec3 HorizonGridColor(float HorizonR, vec2 HorizonRadii,
                      bool IngoingBranch, float HorizonEnergy)
{
    vec3 Hue = HorizonR == HorizonRadii.x ? vec3(0.0, 1.0, 0.0)
                                         : vec3(1.0, 0.0, 0.0);
    if (HorizonRadii.x == HorizonRadii.y) Hue = vec3(0.0, 0.6, 1.0);

    vec3 Color = IngoingBranch ? 0.6 * Hue : mix(Hue, vec3(1.0), 0.55);
    if (HorizonEnergy < 0.0) {
        float cMax = max(max(Color.r, Color.g), Color.b);
        float cMin = min(min(Color.r, Color.g), Color.b);
        Color = vec3(cMax + cMin) - Color;
        if (iWhitehole == 0) Color = vec3(0.0);
    }
    return Color;
}

// 将共转经线转到该分支的正则 KS 参考系；先解析消去本视界的对数项。
// phi_in = phi_out - G，T_in = T_out + F，故相位差为 Omega_H F - G。
float HorizonGridPhase(vec4 HitX, float HorizonR, float a,
                       bool isoutgoing, bool IngoingBranch)
{
    float OmegaH = a / (HorizonR * HorizonR + a * a);
    float Phi = atan(HitX.z, abs(HitX.x) + abs(HitX.z) > 1e-12 ? HitX.x : 1.0);
    Phi += OmegaH * HitX.w + OmegaH * iBlackHoleTime;
    if (a == 0.0 || isoutgoing != IngoingBranch) return Phi;

    float OtherHorizonR = 2.0 * CONST_M - HorizonR;
    float HorizonGap = abs(HorizonR - OtherHorizonR);
    // 极端重合视界没有有限的两系相位拼接；只使用交点所在的正则系。
    if (HorizonGap == 0.0) return Phi;
    float PhaseShift = 4.0 * CONST_M * OmegaH * log(HorizonGap) - 2.0 * atan(a, HorizonR);
    return Phi + (IngoingBranch ? PhaseShift : -PhaseShift);
}

vec4 GridColorSimple(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
               vec4 P_cov, vec4 LastP_cov, 
               float PhysicalSpinA, float PhysicalQ2, bool isoutgoing,
               float EndStepSign, float dlambda,bool showInnerGrid)
               {
    vec4 CurrentResult = BaseColor;
    if (CurrentResult.a > 0.99) return CurrentResult;

    const int MaxGrids = 5; 
    
    float SignedGridRadii[MaxGrids]; 
    vec3  GridColors[MaxGrids];
    bool  IsHorizonGrid[MaxGrids];
    int   GridCount = 0;
    
    float StartStepSign = GetIntermediateSign(RayPos, LastRayPos, EndStepSign, PhysicalSpinA);
    bool bHasCrossed = StartStepSign != EndStepSign;
    float t_cross = -1.0;
    vec3 DiskHitPos = vec3(0.0);
    vec4 DiskHitX = vec4(0.0); // 用于记录赤道盘相交时的四维坐标信息

    // --- 计算端点坐标速度与 Hermite 曲线切线 ---
    // 获取起点和终点的几何信息并升指标，求出坐标对仿射参量的导数 dX/dlambda
    KerrGeometry geo_last;
    ComputeGeometryScalars(LastRayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, StartStepSign, isoutgoing, geo_last);
    vec4 V0 = RaiseIndex(LastP_cov, geo_last); 
    vec4 T0 = V0 * dlambda; // 转换为对插值参数 t(0~1) 的导数

    KerrGeometry geo_curr;
    ComputeGeometryScalars(RayPos.xyz, PhysicalSpinA, PhysicalQ2, 1.0, EndStepSign, isoutgoing, geo_curr);
    vec4 V1 = RaiseIndex(P_cov, geo_curr);     
    vec4 T1 = V1 * dlambda; 

// --- 赤道盘相交改为三次曲线求根 ---
    if (LastRayPos.y * RayPos.y < 0.0) {
        float denom = (LastRayPos.y - RayPos.y);
        if (denom != 0.0) {
            t_cross = LastRayPos.y / denom; // 线性初猜
            
            // 牛顿迭代求三次 Hermite 曲线在 y 轴的精确零点
            for(int iter = 0; iter < 3; iter++) {
                float t2 = t_cross * t_cross;
                float t3 = t2 * t_cross;
                
                // 基函数
                float h00 = 2.0*t3 - 3.0*t2 + 1.0;
                float h10 = t3 - 2.0*t2 + t_cross;
                float h01 = -2.0*t3 + 3.0*t2;
                float h11 = t3 - t2;
                float yt = h00*LastRayPos.y + h10*T0.y + h01*RayPos.y + h11*T1.y;
                
                // 导数
                float dh00 = 6.0*t2 - 6.0*t_cross;
                float dh10 = 3.0*t2 - 4.0*t_cross + 1.0;
                float dh01 = -6.0*t2 + 6.0*t_cross;
                float dh11 = 3.0*t2 - 2.0*t_cross;
                float dyt = dh00*LastRayPos.y + dh10*T0.y + dh01*RayPos.y + dh11*T1.y;
                
                if (abs(dyt) < 1e-30) break;
                t_cross -= yt / dyt;
            }
            t_cross = clamp(t_cross, 0.0, 1.0);
            
            // 依据精确 t 计算交点四维坐标
            float t2 = t_cross * t_cross;
            float t3 = t2 * t_cross;
            vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t_cross, -2.0*t3 + 3.0*t2, t3 - t2);
            DiskHitX = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
            DiskHitPos = DiskHitX.xyz;
            
            // 分支符号沿用主光路的穿盘判定，插值只细化交点。
        }
    }
    // ---------------------------------------------

    bool CheckPositive = (StartStepSign > 0.0) || (EndStepSign > 0.0);
    bool CheckNegative = (StartStepSign < 0.0) || (EndStepSign < 0.0);

    float HorizonDiscrim = 0.25 - (PhysicalSpinA * PhysicalSpinA + PhysicalQ2);
    vec2 HorizonRadii = KerrHorizonRadii(PhysicalSpinA, PhysicalQ2);
    float RH_Outer = HorizonRadii.x;
    float RH_Inner = HorizonRadii.y;
    bool HasHorizon = HorizonDiscrim >= 0.0;

    if (CheckPositive) {
        SignedGridRadii[GridCount] = 70.0;
        GridColors[GridCount] = 0.3*vec3(0.0, 1.0, 1.0);
        IsHorizonGrid[GridCount] = false; 
        GridCount++;

        if (HasHorizon) {
            SignedGridRadii[GridCount] = RH_Outer; 
            GridColors[GridCount] = 0.3*vec3(0.0, 1.0, 0.0);
            IsHorizonGrid[GridCount] = true; 
            GridCount++;
            if (showInnerGrid && RH_Inner > 0.0 && RH_Inner != RH_Outer)
            {
                SignedGridRadii[GridCount] = RH_Inner; 
                GridColors[GridCount] = 0.3 * vec3(1.0, 0.0, 0.0);
                IsHorizonGrid[GridCount] = true; 
                GridCount++;
            }
        }
    }
    
    if (CheckNegative) {
        SignedGridRadii[GridCount] = -70.0;  
        GridColors[GridCount] = 0.3*vec3(1.0, 0.0, 1.0);
        IsHorizonGrid[GridCount] = false; 
        GridCount++;
        if (HasHorizon && RH_Inner < 0.0 && showInnerGrid) {
            SignedGridRadii[GridCount] = RH_Inner;
            GridColors[GridCount] = 0.3 * vec3(1.0, 0.0, 0.0);
            IsHorizonGrid[GridCount] = true;
            GridCount++;
        }
    }

    vec3 O = LastRayPos.xyz;
    vec3 D_vec = RayPos.xyz - LastRayPos.xyz;

    for (int i = 0; i < GridCount; i++) {
        if (CurrentResult.a > 0.99) break;

        float TargetSignedR = SignedGridRadii[i];
        float TargetGeoR = abs(TargetSignedR); 
        vec3  TargetColor = GridColors[i];

        vec2 roots = IntersectGridEllipsoid(O, D_vec, TargetGeoR, PhysicalSpinA);
        
        float t_hits[2];
        t_hits[0] = roots.x;
        t_hits[1] = roots.y;
        if (t_hits[0] > t_hits[1]) {
            float temp = t_hits[0]; t_hits[0] = t_hits[1]; t_hits[1] = temp;
        }
        
        for (int j = 0; j < 2; j++) {
            float t = t_hits[j];
            
            if (t > 0.0 && t <= 1.0) {
                
                float HitPointSign = StartStepSign;
                if (bHasCrossed) {
                    if (t > t_cross) {
                        HitPointSign = EndStepSign;
                    }
                }

                // 在原系细化交点。椭球的解析法向不需要对 r 做差分。
                float r2 = TargetGeoR * TargetGeoR;
                vec3 InvAxisSq = vec3(1.0 / (r2 + PhysicalSpinA * PhysicalSpinA),
                                     1.0 / r2,
                                     1.0 / (r2 + PhysicalSpinA * PhysicalSpinA));
                for (int iter = 0; iter < 3; iter++) {
                    float t2 = t * t;
                    float t3 = t2 * t;
                    vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
                    vec4 dH = vec4(6.0*t2 - 6.0*t, 3.0*t2 - 4.0*t + 1.0, -6.0*t2 + 6.0*t, 3.0*t2 - 2.0*t);
                    vec3 Pos = (H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1).xyz;
                    vec3 Tangent = (dH.x*LastRayPos + dH.y*T0 + dH.z*RayPos + dH.w*T1).xyz;
                    vec3 Normal = Pos * InvAxisSq;
                    float Slope = 2.0 * dot(Normal, Tangent);
                    if (abs(Slope) < 1e-20) break;
                    t -= (dot(Pos, Normal) - 1.0) / Slope;
                }
                if (!(t > 0.0 && t <= 1.0)) continue;
                if (j == 1 && abs(t - t_hits[0]) < 1e-6) continue;
                t_hits[j] = t;

                // 依据精确 t 提取四维坐标
                float t2 = t*t; float t3 = t2*t;
                vec4 H = vec4(2.0*t3 - 3.0*t2 + 1.0, t3 - 2.0*t2 + t, -2.0*t3 + 3.0*t2, t3 - t2);
                vec4 HitX = H.x*LastRayPos + H.y*T0 + H.z*RayPos + H.w*T1;
                
                vec3 HitPos = HitX.xyz;
                float HitTime = HitX.w;
                // ----------------------------------------------------
                
                HitPointSign = (bHasCrossed && t > t_cross) ? EndStepSign : StartStepSign;
                if (HitPointSign * TargetSignedR < 0.0) continue;
                if (abs(dot(HitPos, HitPos * InvAxisSq) - 1.0) > 1e-4) continue; 

                // 动量在此保持线性插值即可（已足够准确用于后续投影运算）
                vec4 HitP_cov = mix(LastP_cov, P_cov, t);
                bool IngoingBranch = !isoutgoing;
                float HorizonEnergy = 0.0;
                if (IsHorizonGrid[i]) {
                    KerrGeometry geo_hit;
                    ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ2, 1.0, HitPointSign, isoutgoing, geo_hit);
                    IngoingBranch = IsIngoingHorizonGridRay(HitX, HitP_cov, geo_hit,
                                                          TargetSignedR, PhysicalSpinA, isoutgoing, HorizonEnergy);
                }

                // 普通网格使用 Ingoing 纹理；真实视界按分支使用正则共转相位。
                vec3 PatternPos = HitPos;
                float PatternTime = HitTime;
                if (isoutgoing && !IsHorizonGrid[i]) {
                    vec4 tempX = vec4(HitPos, HitTime);
                    vec4 dummyP = vec4(0.0);
                    transformKerrSchild_YSpin(tempX, HitPointSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
                    PatternPos = tempX.xyz;
                    PatternTime = tempX.w;
                }

                float Omega = IsHorizonGrid[i]
                    ? PhysicalSpinA / (TargetSignedR * TargetSignedR + PhysicalSpinA * PhysicalSpinA)
                    : GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ2, PatternPos.y);

                float Phi_raw = atan(PatternPos.z, abs(PatternPos.x) + abs(PatternPos.z) > 1e-12 ? PatternPos.x : 1.0);
                float BaseOmega = IsHorizonGrid[i] ? Omega : GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ2, 0.0);
                float Phi = Phi_raw + Omega * PatternTime + BaseOmega * iBlackHoleTime;
                if (IsHorizonGrid[i]) {
                    Phi = HorizonGridPhase(HitX, TargetSignedR, PhysicalSpinA, isoutgoing, IngoingBranch);
                }
                
                float CosTheta = clamp(PatternPos.y / TargetGeoR, -1.0, 1.0);
                float Theta = acos(CosTheta);
                float SinTheta = sqrt(max(0.0, 1.0 - CosTheta * CosTheta));

                float DensityPhi = 24.0;
                float DensityTheta = 13.0;
                float DistFactor = min(20.0,length(PatternPos));
                float LineWidth = 0.002 * DistFactor; 
                LineWidth = clamp(LineWidth, 0.01, 0.15); 

                float PatternPhi = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
                float GridPhi = (1.0 - smoothstep(0.0, LineWidth / max(0.005, SinTheta), PatternPhi));

                float PatternTheta = abs(fract(Theta / kPi * DensityTheta) - 0.5);
                float GridTheta = (1.0 - smoothstep(0.0, LineWidth, PatternTheta));
                
                float GridIntensity = max(GridPhi, GridTheta);

                float E_emit = 1.0;
                if (!IsHorizonGrid[i]) {
                    float Omega_zamo = GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ2, HitPos.y);
                    vec3 VelSpatial = Omega_zamo * vec3(HitPos.z, 0.0, -HitPos.x);
                    vec4 U_zamo_unnorm = vec4(VelSpatial, 1.0);
                    KerrGeometry geo_hit;
                    ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ2, 1.0, HitPointSign, isoutgoing, geo_hit);
                    vec4 U_zamo_lower = LowerIndex(U_zamo_unnorm, geo_hit);
                    float norm_sq = dot(U_zamo_unnorm, U_zamo_lower);
                    vec4 U_zamo = U_zamo_unnorm / sqrt(max(1e-9, abs(norm_sq)));
                    E_emit = -dot(HitP_cov, U_zamo);
                }

                if (GridIntensity > 0.01) {
                    vec4 GridCol = vec4(TargetColor * 2.0, 1.0);
                    if (IsHorizonGrid[i]) {
                        GridCol.rgb = HorizonGridColor(TargetSignedR, HorizonRadii, IngoingBranch, HorizonEnergy);//视界面的负能剔除在这个函数内部
                    }
                    else if (E_emit < 0.0) {
                        float cMax = max(max(GridCol.r, GridCol.g), GridCol.b);
                        float cMin = min(min(GridCol.r, GridCol.g), GridCol.b);
                        GridCol.rgb = vec3(cMax + cMin) - GridCol.rgb;
                        if (iWhitehole == 0) GridCol.rgba = vec4(0.0);
                    }
                    // -----------------------------------------
                    
                    float Alpha = GridIntensity * 0.8 * GridCol.a; 
                    CurrentResult.rgb += GridCol.rgb * Alpha * (1.0 - CurrentResult.a);
                    CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
                }
            }
        }
    }

    if (bHasCrossed && CurrentResult.a < 0.99) {
        
        float HitRho = length(DiskHitPos.xz);
        float a_abs = abs(PhysicalSpinA);
        float HitTime_disk = DiskHitX.w;
        vec4 HitP_cov = mix(LastP_cov, P_cov, t_cross);
        // --- 提取统一网格相位的偏移 ---
        vec3 PatternPosDisk = DiskHitPos;
        if (isoutgoing) {
            vec4 tempX = vec4(DiskHitPos, HitTime_disk);
            vec4 dummyP = vec4(0.0);
            float diskSign = (length(DiskHitPos.xz) < abs(PhysicalSpinA)) ? -StartStepSign : StartStepSign;
            transformKerrSchild_YSpin(tempX, diskSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
            PatternPosDisk = tempX.xyz;
        }

        float Phi_raw = atan(PatternPosDisk.z, abs(PatternPosDisk.x) + abs(PatternPosDisk.z) > 1e-12 ? PatternPosDisk.x : 1.0);
        float Phi = Phi_raw;
        
        float DensityPhi = 24.0;
        float DistFactor = length(DiskHitPos); 
        float LineWidth = 0.002 * DistFactor;
        LineWidth = clamp(LineWidth, 0.01, 0.1);

        float PatternPhi = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
        float GridPhi = (1.0 - smoothstep(0.0, LineWidth / max(0.1, HitRho / a_abs), PatternPhi));

        float NormalizedRho = HitRho / max(1e-6, a_abs);
        float DensityRho = 5.0; 
        float PatternRho = abs(fract(NormalizedRho * DensityRho) - 0.5);
        float GridRho = (1.0 - smoothstep(0.0, LineWidth, PatternRho));
        
        float GridIntensity = max(GridPhi, GridRho);

        // --- 计算静态能量投影 ---
        vec4 U_zero = vec4(0.0, 0.0, 0.0, 1.0); 
        float E_emit_disk = -dot(HitP_cov, U_zero); 
        // ---------------------------------

        if (GridIntensity > 0.01) {
            vec3 RingColor = 0.3*vec3(1.0, 1.0, 1.0);
            vec4 GridCol = vec4(RingColor * 5.0, 1.0);
            
            // --- 负能量判断与反色/剔除逻辑 ---
            if (E_emit_disk < 0.0) {
                float cMax = max(max(GridCol.r, GridCol.g), GridCol.b);
                float cMin = min(min(GridCol.r, GridCol.g), GridCol.b);
                GridCol.rgb = vec3(cMax + cMin) - GridCol.rgb;
                if (iWhitehole == 0) GridCol.rgba = vec4(0.0);
            }
            // -----------------------------------------
            
            float Alpha = GridIntensity * 0.8 * GridCol.a;
            CurrentResult.rgb += GridCol.rgb * Alpha * (1.0 - CurrentResult.a);
            CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
        }
    }

    return CurrentResult;
}

vec4 GridColor(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
               vec4 iP_cov, float iE_obs,
               float PhysicalSpinA, float PhysicalQ2, bool isoutgoing,
               float EndStepSign)
{
    vec4 CurrentResult = BaseColor;
    if (CurrentResult.a > 0.99) return CurrentResult;

    const int MaxGrids = 12; 
    float SignedGridRadii[MaxGrids];
    bool IsHorizonGrid[MaxGrids]; 
    int GridCount = 0;
    
    float StartStepSign = EndStepSign;
    bool bHasCrossed = false;
    float t_cross = -1.0;
    vec3 DiskHitPos = vec3(0.0);
    
    if (LastRayPos.y * RayPos.y < 0.0) {
        float denom = (LastRayPos.y - RayPos.y);
        if(abs(denom) > 1e-9) {
            t_cross = LastRayPos.y / denom;
            DiskHitPos = mix(LastRayPos.xyz, RayPos.xyz, t_cross);
            
            if (length(DiskHitPos.xz) < abs(PhysicalSpinA)) {
                StartStepSign = -EndStepSign;
                bHasCrossed = true;
            }
        }
    }

    bool CheckPositive = (StartStepSign > 0.0) || (EndStepSign > 0.0);
    bool CheckNegative = (StartStepSign < 0.0) || (EndStepSign < 0.0);

    float HorizonDiscrim = 0.25 - (PhysicalSpinA * PhysicalSpinA + PhysicalQ2);
    vec2 HorizonRadii = KerrHorizonRadii(PhysicalSpinA, PhysicalQ2);
    float RH_Outer = HorizonRadii.x;
    float RH_Inner = HorizonRadii.y;

    if (CheckPositive) {
        if (HorizonDiscrim >= 0.0) {
            IsHorizonGrid[GridCount] = true;
            SignedGridRadii[GridCount++] = RH_Outer;
        }
        IsHorizonGrid[GridCount] = false;
        SignedGridRadii[GridCount++] = 20.0;

        if (HorizonDiscrim >= 0.0 && RH_Inner > 0.0 && RH_Inner != RH_Outer) {
            IsHorizonGrid[GridCount] = true;
            SignedGridRadii[GridCount++] = RH_Inner;
        }
    }

    if (CheckNegative) {
        IsHorizonGrid[GridCount] = false;
        SignedGridRadii[GridCount++] = -3.0;
        IsHorizonGrid[GridCount] = false;
        SignedGridRadii[GridCount++] = -10.0;
        if (HorizonDiscrim >= 0.0 && RH_Inner < 0.0) {
            IsHorizonGrid[GridCount] = true;
            SignedGridRadii[GridCount++] = RH_Inner;
        }
    }

    vec3 O = LastRayPos.xyz;
    vec3 D_vec = RayPos.xyz - LastRayPos.xyz;

    for (int i = 0; i < GridCount; i++) {
        if (CurrentResult.a > 0.99) break;

        float TargetSignedR = SignedGridRadii[i];
        float TargetGeoR = abs(TargetSignedR); 

        vec2 roots = IntersectGridEllipsoid(O, D_vec, TargetGeoR, PhysicalSpinA);
        
        float t_hits[2];
        t_hits[0] = roots.x;
        t_hits[1] = roots.y;
        
        if (t_hits[0] > t_hits[1]) {
            float temp = t_hits[0]; t_hits[0] = t_hits[1]; t_hits[1] = temp;
        }
        
        for (int j = 0; j < 2; j++) {
            float t = t_hits[j];
            
            if (t > 0.0 && t <= 1.0) {
                
                float HitPointSign = StartStepSign;
                if (bHasCrossed) {
                    if (t > t_cross) {
                        HitPointSign = EndStepSign;
                    }
                }

                if (HitPointSign * TargetSignedR < 0.0) continue;

                vec3 HitPos = O + D_vec * t;
                float CheckR = KerrSchildRadius(HitPos, PhysicalSpinA, HitPointSign);
                if (abs(CheckR - TargetSignedR) > 0.1 * TargetGeoR + 0.1) continue; 

                float HitTime = mix(LastRayPos.w, RayPos.w, t);
                vec4 HitX = vec4(HitPos, HitTime);

                KerrGeometry geo_hit;
                ComputeGeometryScalars(HitPos, PhysicalSpinA, PhysicalQ2, 1.0, HitPointSign, isoutgoing, geo_hit);
                bool IngoingBranch = !isoutgoing;
                float HorizonEnergy = 0.0;
                float Omega;
                float Shift = 1.0;
                if (IsHorizonGrid[i]) {
                    Omega = PhysicalSpinA / (TargetSignedR * TargetSignedR + PhysicalSpinA * PhysicalSpinA);
                    IngoingBranch = IsIngoingHorizonGridRay(HitX, iP_cov, geo_hit,
                                                          TargetSignedR, PhysicalSpinA, isoutgoing, HorizonEnergy);
                } else {
                    Omega = GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ2, HitPos.y);
                    vec3 VelSpatial = Omega * vec3(HitPos.z, 0.0, -HitPos.x);
                    vec4 U_zamo_unnorm = vec4(VelSpatial, 1.0);
                    vec4 U_zamo_lower = LowerIndex(U_zamo_unnorm, geo_hit);
                    float norm_sq = dot(U_zamo_unnorm, U_zamo_lower);
                    vec4 U_zamo = U_zamo_unnorm / sqrt(max(1e-9, abs(norm_sq)));
                    float E_emit = -dot(iP_cov, U_zamo);
                    Shift = 1.0 / max(1e-6, abs(E_emit));
                }

                // 普通网格使用 Ingoing 纹理；视界忽略频移，直接显示几何分支。
                vec3 PatternPos = HitPos;
                float PatternTime = HitTime;
                if (isoutgoing && !IsHorizonGrid[i]) {
                    vec4 tempX = vec4(HitPos, HitTime);
                    vec4 dummyP = vec4(0.0);
                    // out_to_in = true 转换为 Ingoing
                    transformKerrSchild_YSpin(tempX, HitPointSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
                    PatternPos = tempX.xyz;
                    PatternTime = tempX.w;
                }

                float Phi_raw = atan(PatternPos.z, abs(PatternPos.x) + abs(PatternPos.z) > 1e-12 ? PatternPos.x : 1.0);
                float BaseOmega = IsHorizonGrid[i] ? Omega : GetZamoOmega(TargetSignedR, PhysicalSpinA, PhysicalQ2, 1.0);
                float Phi = Phi_raw + Omega * PatternTime + BaseOmega * iBlackHoleTime;
                if (IsHorizonGrid[i]) {
                    Phi = HorizonGridPhase(HitX, TargetSignedR, PhysicalSpinA, isoutgoing, IngoingBranch);
                }
                
                float CosTheta = clamp(PatternPos.y / TargetGeoR, -1.0, 1.0);
                float Theta = acos(CosTheta);
                float SinTheta = sqrt(max(0.0, 1.0 - CosTheta * CosTheta));

                float DensityPhi = 24.0;
                float DensityTheta = 12.0;
                float DistFactor = length(PatternPos);
                float LineWidth = 0.001 * DistFactor;
                LineWidth = clamp(LineWidth, 0.01, 0.1); 

                float PatternPhi = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
                float GridPhi = (1.0 - smoothstep(0.0, LineWidth / max(0.005, SinTheta), PatternPhi));

                float PatternTheta = abs(fract(Theta / kPi * DensityTheta) - 0.5);
                float GridTheta = (1.0 - smoothstep(0.0, LineWidth, PatternTheta));
                
                float GridIntensity = max(GridPhi, GridTheta);

                if (GridIntensity > 0.01) {
                    vec4 GridCol;
                    if (IsHorizonGrid[i]) {
                        GridCol = vec4(HorizonGridColor(TargetSignedR, HorizonRadii, IngoingBranch, HorizonEnergy), 1.0);
                    } else {
                        float BaseTemp = 6500.0;
                        vec3 BlackbodyColor = KelvinToRgb(BaseTemp * Shift);
                        float Intensity = min(1.5 * pow(Shift, 4.0), 20.0);
                        GridCol = vec4(BlackbodyColor * Intensity, 1.0);
                    }
                    float Alpha = GridIntensity * 0.5; 
                    CurrentResult.rgb += GridCol.rgb * Alpha * (1.0 - CurrentResult.a);
                    CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
                }
            }
        }
    }

    // --- 赤道面的网格处理同样映射为统一相空间 ---
    if (bHasCrossed && CurrentResult.a < 0.99) {
        
        float HitRho = length(DiskHitPos.xz);
        float a_abs = abs(PhysicalSpinA);
        float HitTime_disk = mix(LastRayPos.w, RayPos.w, t_cross);
        
        vec3 PatternPosDisk = DiskHitPos;
        if (isoutgoing) {
            vec4 tempX = vec4(DiskHitPos, HitTime_disk);
            vec4 dummyP = vec4(0.0);
            float diskSign = (length(DiskHitPos.xz) < abs(PhysicalSpinA)) ? -StartStepSign : StartStepSign;
            transformKerrSchild_YSpin(tempX, diskSign, dummyP, 0.5, PhysicalSpinA, PhysicalQ2, true);
            PatternPosDisk = tempX.xyz;
        }

        float Phi_raw = atan(PatternPosDisk.z, abs(PatternPosDisk.x) + abs(PatternPosDisk.z) > 1e-12 ? PatternPosDisk.x : 1.0);
        float Phi = Phi_raw;
        
        float DensityPhi = 24.0;
        float DistFactor = length(DiskHitPos); 
        float LineWidth = 0.001 * DistFactor;
        LineWidth = clamp(LineWidth, 0.01, 0.1);

        float PatternPhi = abs(fract(Phi / (2.0 * kPi) * DensityPhi) - 0.5);
        float GridPhi = (1.0 - smoothstep(0.0, LineWidth / max(0.1, HitRho / a_abs), PatternPhi));

        float NormalizedRho = HitRho / max(1e-6, a_abs);
        float DensityRho = 5.0; 
        float PatternRho = abs(fract(NormalizedRho * DensityRho) - 0.5);
        float GridRho = (1.0 - smoothstep(0.0, LineWidth, PatternRho));
        
        float GridIntensity = max(GridPhi, GridRho);

        if (GridIntensity > 0.01) {
            // (频移由于和空间无关依然使用原始数据)
            vec4 U_zero = vec4(0.0, 0.0, 0.0, 1.0); 
            float E_emit = -dot(iP_cov, U_zero); 
            float Shift = 1.0 / max(1e-6, abs(E_emit));
            
            float BaseTemp = 6500.0; 
            vec3 BlackbodyColor = KelvinToRgb(BaseTemp * Shift);
            float Intensity = min(2.0 * pow(Shift, 4.0), 30.0);
            
            vec4 GridCol = vec4(BlackbodyColor * Intensity, 1.0);
            
            float Alpha = GridIntensity * 0.5;
            CurrentResult.rgb += GridCol.rgb * Alpha * (1.0 - CurrentResult.a);
            CurrentResult.a   += Alpha * (1.0 - CurrentResult.a);
        }
    }

    return CurrentResult;
}

// =====================================================================
// Falling test sphere, stage 1: local continuous surface intersection.
// Replaces only GetTestParticleDistSq / DrawFallingTestParticle and their
// private helpers. No extra geodesic integration and no caller changes.
// The original Schwarzschild coordinate-sphere model is retained.
// =====================================================================
const vec3  FTP_INITIAL_POS = vec3(100.0, 0.0, 0.1);
const float FTP_RADIUS = 0.05;
const float FTP_END_RADIUS = 0.02;
const int   FTP_MAX_INTERVALS = 32;
const int   FTP_ROOT_ITERS = 12;
const float FTP_MIN_SPAN = 1.0 / 4096.0;

struct FTP_Curve {
    vec4 c0, c1, c2, c3;   // native-chart cubic; parameter s runs from 0 to 1
    float a, Q2, signR;
    bool outgoing;
};

struct FTP_Sample {
    vec4 X;                // Ingoing coordinates, including the time lag
    vec4 tangent;          // dX_in / ds, NOT a normalized spatial direction
    vec3 q;                // photon minus simultaneous sphere centre
    float r;
    float targetF;
    bool alive;
};

float FTP_F(float r) {
    float u = sqrt(max(r, 0.0));
    // Equivalent to the original F(r); the small-r series avoids subtracting
    // nearly equal linear terms. It is only used near the existing cutoff.
    if (u < 0.15) {
        return -r + r*r * (-0.5 + u * (0.4 + u * (-1.0/3.0
             + u * (2.0/7.0 + u * (-0.25 + u * (2.0/9.0
             + u * (-0.2 + u * (2.0/11.0))))))));
    }
    return -(2.0/3.0)*r*u - 2.0*u + 2.0*log(1.0 + u);
}

float FTP_RadiusAtF(float targetF) {
    // Hold the *bounding* trajectory at END_RADIUS after disappearance.
    // FTP_Sample.alive independently prevents drawing this continuation.
    float cutF = FTP_F(FTP_END_RADIUS);
    if (targetF >= cutF) return FTP_END_RADIUS;
    float lo = FTP_END_RADIUS;
    float hi = max(lo, pow(-1.5*targetF, 2.0/3.0));
    float r = hi;
    for (int i = 0; i < 7; ++i) {
        float u = sqrt(r);
        float f = FTP_F(r) - targetF;
        if (abs(f) <= 1e-7 * max(1.0, abs(targetF))) break;
        if (f < 0.0) hi = r; else lo = r;
        float trial = r + f / (u + 1.0/(u + 1.0));
        r = (trial > lo && trial < hi) ? trial : 0.5*(lo + hi);
    }
    return max(r, FTP_END_RADIUS);
}

void FTP_Native(FTP_Curve c, float s, out vec4 X, out vec4 dX) {
    X = c.c0 + s*(c.c1 + s*(c.c2 + s*c.c3));
    dX = c.c1 + s*(2.0*c.c2 + 3.0*s*c.c3);
}

// Compensated norm difference, used only by the Schwarzschild Out -> In
// map. Computing length(X)-1 after rounding X loses almost all useful bits
// close to the horizon; splitting the native cubic into origin + offset
// also prevents its tiny radial motion from disappearing during root finding.
vec2 FTP_TwoSum(float a, float b) {
    float sum=a+b;
    float v=sum-a;
    float error=(a-(sum-v))+(b-v);
    return vec2(sum,error);
}

float FTP_NormSqMinusOne(vec3 x) {
    vec3 sq=x*x;
    vec3 rem=fma(x,x,-sq);
    vec2 a=FTP_TwoSum(sq.x,sq.y);
    vec2 b=FTP_TwoSum(a.x,sq.z);
    vec2 c=FTP_TwoSum(b.x,-1.0);
    return c.x+(a.y+b.y+c.y+rem.x+rem.y+rem.z);
}

FTP_Sample FTP_Evaluate(FTP_Curve c, float s) {
    FTP_Sample p;
    FTP_Native(c, s, p.X, p.tangent);
    if (c.outgoing) {
        if (c.a == 0.0 && c.Q2 == 0.0 && c.signR > 0.0) {
            // Exact Schwarzschild Out -> In map, without transforming a
            // dummy covector and subtracting its large near-horizon terms.
            vec4 offset=s*(c.c1+s*(c.c2+s*c.c3));
            float originNorm=FTP_NormSqMinusOne(c.c0.xyz);
            float normDelta=originNorm+2.0*dot(c.c0.xyz,offset.xyz)
                                     +dot(offset.xyz,offset.xyz);
            float r=sqrt(max(0.0,1.0+normDelta));
            float gap=normDelta/(r+1.0);
            float gap0=originNorm/(length(c.c0.xyz)+1.0);
            float absGap=max(abs(gap),1e-16), absGap0=max(abs(gap0),1e-16);
            float safeGap=(gap<0.0 ? -1.0 : 1.0)*absGap;
            float drds=dot(p.X.xyz,p.tangent.xyz)/max(r,1e-20);
            p.X.w=(c.c0.w+2.0*log(absGap0))
                  +(offset.w+2.0*log(absGap/absGap0));
            p.tangent.w+=2.0*drds/safeGap;
        } else {
            // Compatibility with the old visual test at other parameters.
            // This does NOT turn the retained trajectory into a KN fall.
            KerrGeometry g0, g1;
            ComputeGeometryScalars(p.X.xyz, c.a, c.Q2, 1.0, c.signR, true, g0);
            vec4 cov = LowerIndex(p.tangent, g0);
            transformKerrSchild_YSpin(p.X, c.signR, cov, 0.5, c.a, c.Q2, true);
            ComputeGeometryScalars(p.X.xyz, c.a, c.Q2, 1.0, c.signR, false, g1);
            p.tangent = RaiseIndex(cov, g1);
        }
    }
    // Cancel the large common time offset BEFORE adding the small ray lag.
    p.targetF = (iBlackHoleTime + FTP_F(length(FTP_INITIAL_POS))) + p.X.w;
    p.alive = p.targetF <= FTP_F(FTP_END_RADIUS);
    p.r = FTP_RadiusAtF(p.targetF);
    p.q = p.X.xyz - normalize(FTP_INITIAL_POS)*p.r;
    return p;
}

bool FTP_Finite(FTP_Sample p) {
    return !any(isnan(p.X)) && !any(isinf(p.X))
        && !any(isnan(p.q)) && !any(isinf(p.q))
        && !any(isnan(p.tangent)) && !any(isinf(p.tangent));
}

float FTP_Tolerance(FTP_Sample p) {
    // Account for float32 subtraction at large coordinate radii.
    return max(5e-6, 4e-7*max(p.r, length(p.X.xyz)));
}

vec3 FTP_RelativeTangent(FTP_Sample p) {
    float u = sqrt(p.r);
    float vr = p.alive ? -1.0/(u + 1.0/(u + 1.0)) : 0.0;
    return p.tangent.xyz - normalize(FTP_INITIAL_POS)*(vr*p.tangent.w);
}

void FTP_Bezier(FTP_Curve c, float l, float h,
               out vec4 b0, out vec4 b1, out vec4 b2, out vec4 b3) {
    vec4 d0, d1;
    FTP_Native(c, l, b0, d0);
    FTP_Native(c, h, b3, d1);
    b1 = b0 + ((h-l)/3.0)*d0;
    b2 = b3 - ((h-l)/3.0)*d1;
}

float FTP_SegmentDistance(vec3 a, vec3 b, out float u) {
    vec3 d = b-a;
    float dd = dot(d, d);
    u = dd > 1e-30 ? clamp(-dot(a,d)/dd, 0.0, 1.0) : 0.0;
    return length(a + u*d);
}

bool FTP_CylinderMiss(vec4 b0, vec4 b1, vec4 b2, vec4 b3) {
    // All sphere centres lie on INITIAL_POS's radial axis. A cubic lies in
    // its control hull, so this transverse AABB rejects entire intervals,
    // not just sampled points. Only used when the spatial chart is unchanged.
    vec3 n = normalize(FTP_INITIAL_POS);
    vec3 side = normalize(vec3(-n.z, 0.0, n.x));
    vec2 p0 = vec2(b0.y, dot(b0.xyz, side));
    vec2 p1 = vec2(b1.y, dot(b1.xyz, side));
    vec2 p2 = vec2(b2.y, dot(b2.xyz, side));
    vec2 p3 = vec2(b3.y, dot(b3.xyz, side));
    vec2 lower = min(min(p0,p1),min(p2,p3));
    vec2 upper = max(max(p0,p1),max(p2,p3));
    vec2 nearest = max(max(lower,-upper),vec2(0.0));
    float pad = 4e-7*max(1.0, max(length(b0.xyz),length(b3.xyz)));
    return dot(nearest,nearest) > (FTP_RADIUS+pad)*(FTP_RADIUS+pad);
}

float FTP_ChordError(FTP_Curve c, float l, float h,
                     FTP_Sample p0, FTP_Sample p1,
                     vec4 b0, vec4 b1, vec4 b2, vec4 b3,
                     out bool allDead) {
    allDead = false;
    // Differentiate the coefficients, rather than subtracting almost equal
    // absolute control points at very small near-horizon subintervals.
    float ds=h-l;
    vec4 d0=ds*(c.c1+l*(2.0*c.c2+3.0*l*c.c3));
    vec4 d2=ds*(c.c1+h*(2.0*c.c2+3.0*h*c.c3));
    vec4 a0=ds*ds*(2.0*c.c2+6.0*l*c.c3);
    vec4 a1=ds*ds*(2.0*c.c2+6.0*h*c.c3);
    vec4 d1=d0+0.5*a0;
    float spaceA = max(length(a0.xyz),length(a1.xyz));
    float timeV = max(abs(d0.w),max(abs(d1.w),abs(d2.w)));
    float timeA = max(abs(a0.w),abs(a1.w));

    if (c.outgoing && c.a == 0.0 && c.signR > 0.0) {
        // Bound derivatives of T_in = T_out + F_KS(r), over the whole native
        // cubic. A horizon-straddling chart interval must be subdivided.
        float unused;
        float bend = 0.75*max(length(b1.xyz-(2.0*b0.xyz+b3.xyz)/3.0),
                              length(b2.xyz-(b0.xyz+2.0*b3.xyz)/3.0));
        float rlo = max(0.0,FTP_SegmentDistance(b0.xyz,b3.xyz,unused)-bend);
        float rhi = max(max(length(b0.xyz),length(b1.xyz)),
                        max(length(b2.xyz),length(b3.xyz)));
        float f0 = rlo*rlo-rlo+c.Q2;
        float f1 = rhi*rhi-rhi+c.Q2;
        float lowerDelta = min(f0,f1), upperDelta = max(f0,f1);
        if (rlo <= 0.5 && rhi >= 0.5) lowerDelta = min(lowerDelta,c.Q2-0.25);
        if (rlo <= 1e-8 || (lowerDelta <= 0.0 && upperDelta >= 0.0)) return 1e30;
        float deltaMin = min(abs(lowerDelta),abs(upperDelta));
        float numMax = max(abs(rlo-c.Q2),abs(rhi-c.Q2));
        float deltaPrime = max(abs(2.0*rlo-1.0),abs(2.0*rhi-1.0));
        float fPrime = 2.0*numMax/deltaMin;
        float fSecond = 2.0/deltaMin + 2.0*numMax*deltaPrime/(deltaMin*deltaMin);
        float spaceV = max(length(d0.xyz),max(length(d1.xyz),length(d2.xyz)));
        timeV += fPrime*spaceV;
        timeA += fPrime*(spaceA+spaceV*spaceV/rlo) + fSecond*spaceV*spaceV;
    } else if (c.outgoing) {
        // Rotating-chart compatibility path: empirical interpolation error,
        // not a certified interval bound. Stage 1 still targets Schwarzschild.
        FTP_Sample pm = FTP_Evaluate(c,0.5*(l+h));
        if (!FTP_Finite(pm)) return 1e30;
        vec3 q1 = p0.q + ((h-l)/3.0)*FTP_RelativeTangent(p0);
        vec3 q2 = p1.q - ((h-l)/3.0)*FTP_RelativeTangent(p1);
        vec3 middle = 0.125*(p0.q+3.0*q1+3.0*q2+p1.q);
        float bend = 0.75*max(length(q1-(2.0*p0.q+p1.q)/3.0),
                              length(q2-(p0.q+2.0*p1.q)/3.0));
        return 2.0*bend + 8.0*length(pm.q-middle);
    }

    float timeBend = timeA/8.0;
    float cutF = FTP_F(FTP_END_RADIUS);
    allDead = min(p0.targetF,p1.targetF)-timeBend > cutF;
    if (max(p0.targetF,p1.targetF)+timeBend >= cutF) {
        // Clamping the bounding trajectory at disappearance introduces a
        // derivative kink. Use its global |dr/dT| <= 1 Lipschitz bound instead.
        return spaceA/8.0 + timeBend + 0.5*abs(p1.targetF-p0.targetF);
    }
    float rlo = max(0.0,min(p0.r,p1.r)-timeBend);
    float u = sqrt(rlo), den = u*u+u+1.0;
    float speed = (u+1.0)/den;
    float accel = (u+2.0)*(u+1.0)/(2.0*den*den*den);
    // Linear-interpolation error <= max |q''(u)| / 8.
    return (spaceA + speed*timeA + accel*timeV*timeV)/8.0;
}

bool FTP_Refine(FTP_Curve c, float l, float h, FTP_Sample pl,
                FTP_Sample ph, float guess, out float hitS, out FTP_Sample hit) {
    float fl = dot(pl.q,pl.q)-FTP_RADIUS*FTP_RADIUS;
    float fh = dot(ph.q,ph.q)-FTP_RADIUS*FTP_RADIUS;
    if ((fl > 0.0) == (fh > 0.0)) return false;
    float s = clamp(guess,l,h);
    if (abs(fl) < abs(fh)) hit = pl; else hit = ph;
    hitS = abs(fl) < abs(fh) ? l : h;
    float best = min(abs(fl),abs(fh));
    for (int i=0; i<FTP_ROOT_ITERS; ++i) {
        FTP_Sample p = FTP_Evaluate(c,s);
        if (!FTP_Finite(p)) return false;
        float f = dot(p.q,p.q)-FTP_RADIUS*FTP_RADIUS;
        if (abs(f) < best) { best=abs(f); hit=p; hitS=s; }
        float tol = FTP_Tolerance(p);
        if (abs(length(p.q)-FTP_RADIUS) <= tol) { hit=p; hitS=s; return p.alive; }
        if ((f > 0.0) == (fl > 0.0)) { l=s; fl=f; } else { h=s; fh=f; }
        float df = 2.0*dot(p.q,FTP_RelativeTangent(p));
        float nextS = abs(df)>1e-20 ? s-f/df : 0.5*(l+h);
        // Safeguard against leaving the bracket or stagnating at one endpoint.
        float guard = 0.02*(h-l);
        s = (nextS>l+guard && nextS<h-guard) ? nextS : 0.5*(l+h);
    }
    return hit.alive && abs(length(hit.q)-FTP_RADIUS) <= FTP_Tolerance(hit);
}

bool FTP_FirstHit(FTP_Curve c, out float hitS, out FTP_Sample hit) {
    vec4 b0,b1,b2,b3;
    FTP_Bezier(c,0.0,1.0,b0,b1,b2,b3);
    bool fixedSpace = !c.outgoing || c.a == 0.0;
    if (fixedSpace && FTP_CylinderMiss(b0,b1,b2,b3)) return false;

    float l=0.0, span=1.0;
    FTP_Sample pl=FTP_Evaluate(c,l);
    if (!FTP_Finite(pl)) return false;
    for (int trial=0; trial<FTP_MAX_INTERVALS; ++trial) {
        float h=min(1.0,l+span);
        if (h <= l) break;
        FTP_Bezier(c,l,h,b0,b1,b2,b3);
        FTP_Sample ph=FTP_Evaluate(c,h);
        if (!FTP_Finite(ph)) {
            span*=0.5;
            if (span<FTP_MIN_SPAN) break;
            continue;
        }
        float tol=max(FTP_Tolerance(pl),FTP_Tolerance(ph));
        float leftDistance=length(pl.q)-FTP_RADIUS;
        // Starting slightly inside and moving further inward is NOT the
        // first surface event: keep looking for the later exit.
        if (pl.alive && abs(leftDistance)<=tol
            && (leftDistance>=0.0 || dot(pl.q,FTP_RelativeTangent(pl))>=0.0)) {
            hitS=l;hit=pl;return true;
        }
        bool dead;
        float error=FTP_ChordError(c,l,h,pl,ph,b0,b1,b2,b3,dead);
        float closest;
        float d=FTP_SegmentDistance(pl.q,ph.q,closest);
        bool outside = d > FTP_RADIUS+error+tol;
        bool inside = max(length(pl.q),length(ph.q))+error < FTP_RADIUS-tol;
        bool skip = dead || outside || inside
                 || (fixedSpace && FTP_CylinderMiss(b0,b1,b2,b3));
        if (!skip) {
            // Only flatten candidate intervals. Most rays take the cheap hull
            // rejection; no point-count proportional to speed is imposed.
            if (error > 2.0*tol && span > FTP_MIN_SPAN) {span*=0.5;continue;}

            float middleS=mix(l,h,closest);
            FTP_Sample pm=FTP_Evaluate(c,middleS);
            if (!FTP_Finite(pm)) {span*=0.5;continue;}
            float fl=length(pl.q)-FTP_RADIUS;
            float fm=length(pm.q)-FTP_RADIUS;
            float fh=length(ph.q)-FTP_RADIUS;
            float chordLen=length(ph.q-pl.q);
            float halfChord=sqrt(max(0.0,FTP_RADIUS*FTP_RADIUS-d*d));
            float entry=mix(l,h,clamp(closest-halfChord/max(chordLen,1e-20),0.0,1.0));
            float exitS=mix(l,h,clamp(closest+halfChord/max(chordLen,1e-20),0.0,1.0));
            bool found=false;
            if (fl>0.0 && fm<=0.0)
                found=FTP_Refine(c,l,middleS,pl,pm,entry,hitS,hit);
            else if (fl>0.0 && fh<=0.0)
                found=FTP_Refine(c,l,h,pl,ph,entry,hitS,hit);
            else if (fl<0.0 && fm>=0.0)
                found=FTP_Refine(c,l,middleS,pl,pm,exitS,hitS,hit);
            else if (fl<0.0 && fh>=0.0)
                found=FTP_Refine(c,l,h,pl,ph,exitS,hitS,hit);
            if (found) return true;
            // A tangent has no sign change; accept only an actually evaluated
            // point within the same small spatial tolerance as a refined root.
            if (pm.alive && abs(fm)<=FTP_Tolerance(pm)) {hitS=middleS;hit=pm;return true;}
            if (ph.alive && abs(fh)<=FTP_Tolerance(ph)) {hitS=h;hit=ph;return true;}
            if (span>FTP_MIN_SPAN && error>0.25*tol) {span*=0.5;continue;}
        }
        l=h; pl=ph;
        if (l>=1.0) break;
        span=min(2.0*span,1.0-l);
    }
    // A fixed work budget is intentional. An unresolved pathological interval
    // is not a proof of no intersection; it is a bounded-cost rendering miss.
    return false;
}

// Keep the old helper signature for source compatibility; drawing below uses
// the richer evaluator so distances, positions and times cannot get mismatched.
float GetTestParticleDistSq(float tau, vec4 LastRayPos, vec4 RayPos, vec4 T0, vec4 T1,
                            float signR, float a, float Q2, bool isoutgoing,
                            out vec4 exactX_in, out float out_r) {
    FTP_Curve c;
    vec4 delta=RayPos-LastRayPos;
    c.c0=LastRayPos; c.c1=T0;
    c.c2=3.0*delta-2.0*T0-T1; c.c3=T0+T1-2.0*delta;
    c.a=a; c.Q2=Q2; c.signR=signR; c.outgoing=isoutgoing;
    FTP_Sample p=FTP_Evaluate(c,tau);
    exactX_in=p.X;
    out_r=p.alive ? p.r : -1.0;
    return p.alive && FTP_Finite(p) ? dot(p.q,p.q) : 1e30;
}

vec4 FTP_DrawSchwarzschild(vec4 BaseColor, vec4 RayPos, vec4 LastRayPos,
                             vec4 P_cov, vec4 LastP_cov,
                             float PhysicalSpinA, float PhysicalQ2, bool isoutgoing,
                             float EndStepSign, float dlambda) {
    if (BaseColor.a>0.99 || abs(dlambda)<1e-30) return BaseColor;
    KerrGeometry g0,g1;
    ComputeGeometryScalars(LastRayPos.xyz,PhysicalSpinA,PhysicalQ2,1.0,EndStepSign,isoutgoing,g0);
    ComputeGeometryScalars(RayPos.xyz,PhysicalSpinA,PhysicalQ2,1.0,EndStepSign,isoutgoing,g1);
    vec4 T0=dlambda*RaiseIndex(LastP_cov,g0);
    vec4 T1=dlambda*RaiseIndex(P_cov,g1);
    vec4 delta=RayPos-LastRayPos;
    FTP_Curve c;
    c.c0=LastRayPos; c.c1=T0;
    c.c2=3.0*delta-2.0*T0-T1; c.c3=T0+T1-2.0*delta;
    c.a=PhysicalSpinA; c.Q2=PhysicalQ2; c.signR=EndStepSign; c.outgoing=isoutgoing;
    float hitS;
    FTP_Sample hit;
    if (!FTP_FirstHit(c,hitS,hit)) return BaseColor;

    vec3 localPos=normalize(hit.q); // the actual surface event, never a back-projected chord
    vec3 octantColor=step(0.0,localPos)*0.8+0.2;
    float safeX=(abs(localPos.x)+abs(localPos.y)<1e-12) ? 1e-12 : localPos.x;
    float phi=atan(localPos.y,safeX);
    float theta=asin(clamp(localPos.z,-1.0,1.0));
    float checker=mod(floor(phi*8.0)+floor(theta*8.0),2.0);
    vec3 baseAlbedo=octantColor*(checker>0.5 ? 1.0 : 0.0);

    // Shift remains 1, as in the supplied shader. Retain its spectral palette.
    vec3 Scolor=baseAlbedo.r*WavelengthToRgb(645.0)
              +baseAlbedo.g*WavelengthToRgb(510.0)
              +baseAlbedo.b*WavelengthToRgb(440.0);
    Scolor/=max(dot(Scolor,vec3(0.3,0.6,0.1)),0.001);

    // The tangent and metric belong to the very same surface event.
    // No second Hermite formula and no mismatched interpolated momentum.
    KerrGeometry gh;
    ComputeGeometryScalars(hit.X.xyz,PhysicalSpinA,PhysicalQ2,1.0,EndStepSign,false,gh);
    float u=sqrt(hit.r);
    float vr=-1.0/(u+1.0/(u+1.0));
    vec4 V=vec4(normalize(FTP_INITIAL_POS)*vr,1.0);
    float normSq=dot(V,LowerIndex(V,gh));
    if (normSq < -1e-8) {
        // Only the sign is needed while Shift == 1. Positive normalizations
        // of V and |dlambda| cancel; avoid dividing by tiny affine steps.
        float energySign=-dot(LowerIndex(hit.tangent,gh),V)*sign(dlambda);
        if (energySign<0.0) {
            if (iWhitehole==0) return BaseColor;
            float cMax=max(max(Scolor.r,Scolor.g),Scolor.b);
            float cMin=min(min(Scolor.r,Scolor.g),Scolor.b);
            Scolor=vec3(cMax+cMin)-Scolor;
        }
    }
    // A coordinate sphere need not have a timelike surface everywhere near
    // the singularity. Do not use abs(normSq) to manufacture a four-velocity
    // or infer a negative-energy rejection there; retain the debug geometry.
    return vec4(BaseColor.rgb+Scolor*(1.0-BaseColor.a),1.0);
}


// ============================================================================
// Neutral equatorial Kerr--Newman test balls. M=1/2, E=1, Carter Q=0.
// Visibility/performance repair: local clocks, launch-relative primitives,
// exact return reflection, exterior envelopes and checked local phase fits.
// Semi-analytic radial quadrature; NO LUT, descriptor, extra pass or ray RK call.
// All mutable globals below are PRIVATE TO ONE shader invocation (one ray).
// ============================================================================
const float KN_BALL_RADIUS = 0.05;
const float KN_L_OFFSET = 0.02;       // Lcrit +/- 2% of |Lcrit| (numeric Ly order)
const float KN_START_SPREAD = 0.12;   // distinct initial azimuths, radians
const int KN_TIME_ITERS = 10;
const int KN_HIT_INTERVALS = 24;
const int KN_HIT_ROOT_ITERS = 18;
const int KN_QUAD_MAX_PANELS = 32;
const float KN_QUAD_V_SPAN = 0.65;   // 8 Gauss nodes per transformed interval
const float KN_MIN_SPAN = 1.0/4096.0;
const bool KN_REST_SPHERE = true;    // first-order local-rest sphere, not full Fermi Exp
const bool KN_SHOW_RETURN = true;   // continue a genuine positive-r radial bounce

struct KN_Orbit {
    float a, q2, L, k, A;
    float rp, rm, gap, rt, innerDepth;
    float hb, hc, u0, mapCentre, mapScale;
    vec2 uh, sig, hroot;
    vec2 poleP, poleM, resP, resM;
    vec2 initialI, initialJ;
    float phi0;
    bool enabled, simple;
};
KN_Orbit KN_orbits[3];
bool KN_ready = false;
// One exact incoming phase value and a return-reflection constant per orbit.
// No accumulated integration along the ray and no sampled worldline/LUT.
vec2 KN_cachedI[3];
float KN_cachedU[3];
bool KN_cacheValid[3];
vec2 KN_returnConstant[3];
bool KN_returnReady[3];

bool KN_IsFinite(float x) { return !isnan(x) && !isinf(x); }
float KN_Asinh(float x) {
    float y=abs(x);
    return sign(x)*log(y+sqrt(y*y+1.0));
}
float KN_Delta(KN_Orbit o, float r) { return (r-o.rp)*(r-o.rm); }
float KN_R(KN_Orbit o, float r) {
    // E=1 cancels the r^4 coefficient EXACTLY.
    // R=r^3-(L^2+Q^2)r^2+(L-a)^2 r-Q^2(L-a)^2.
    return fma(fma(r-o.A,r,o.k*o.k),r,-o.q2*o.k*o.k);
}
float KN_P(KN_Orbit o, float r) { return fma(r,r,-o.a*o.k); }

bool KN_Captured(KN_Orbit o) {
    // Check the whole interval [r+,infinity), not just R at the launch point.
    // The only interior minimum of this monic cubic is the larger R' root.
    float pp=KN_P(o,o.rp);
    if (!(pp>2e-7*max(o.rp*o.rp+abs(o.a*o.k),1e-15))) return false;
    float d=fma(o.A,o.A,-3.0*o.k*o.k);
    if (d>0.0) {
        float rmin=(o.A+sqrt(d))/3.0;
        if (rmin>o.rp) {
            float val=KN_R(o,rmin);
            float scale=rmin*rmin*rmin+o.A*rmin*rmin
                       +o.k*o.k*(rmin+o.q2);
            // Do not classify a float32-unresolved separatrix as a plunge.
            if (val<=8e-7*max(scale,1e-25)) return false;
        }
    }
    return true;
}

float KN_InnerRAtDepth(KN_Orbit o, float w) {
    // r=rm-w. This version resolves a turning point much closer to rm than
    // subtraction of two float32 radii could resolve.
    float pm=KN_P(o,o.rm);
    float p=fma(w,w-2.0*o.rm,pm);
    float r=o.rm-w;
    return fma(p,p,-w*(o.gap+w)*(r*r+o.k*o.k));
}

void KN_FindTurn(inout KN_Orbit o) {
    if (o.L==0.0) {
        // Exact E=1,L=0 identity: R=(r-Q^2)(r^2+a^2).
        o.rt=o.q2;
        o.innerDepth=o.rm-o.rt;
    } else {
        float lowR=0.0;
        float d=fma(o.A,o.A,-3.0*o.k*o.k);
        if (d>0.0) {
            float rmin=(o.A+sqrt(d))/3.0;
            if (rmin>0.0 && rmin<o.rm && KN_R(o,rmin)<=0.0) lowR=rmin;
        }
        float lo=0.0, hi=o.rm-lowR;
        for (int it=0;it<38;++it) {
            float w=0.5*(lo+hi);
            if (w==lo || w==hi) break;
            if (KN_InnerRAtDepth(o,w)>0.0) lo=w; else hi=w;
        }
        o.innerDepth=0.5*(lo+hi);
        o.rt=o.rm-o.innerDepth;
        if (o.rt<0.0 && o.rt>-2e-7) o.rt=0.0;
    }
    o.hb=3.0*o.rt-o.A;
    o.hc=fma(3.0*o.rt-2.0*o.A,o.rt,o.k*o.k);
    o.u0=sqrt(max(length(FTP_INITIAL_POS)-o.rt,0.0));
    o.mapCentre=0.0;
    o.mapScale=pow(max(o.hc,1e-30),0.25);
    if (o.hb<0.0) {
        float hmin=fma(-0.25*o.hb,o.hb,o.hc);
        if (hmin>0.0) {
            // Remove the sharp whirl peak near a nearly double exterior root.
            o.mapCentre=sqrt(-0.5*o.hb);
            o.mapScale=max(sqrt(hmin)/(2.0*o.mapCentre),1e-10);
        }
    }
}

float KN_H(KN_Orbit o, float u) {
    float z=u*u;
    return max(fma(z+o.hb,z,o.hc),1e-30);
}
float KN_Radius(KN_Orbit o,float u) {
    return max(0.0,o.rm+fma(u,u,-o.innerDepth));
}
vec2 KN_HorizonPrimitive(float r,float a,float q2) {
    // Half of the existing Out->In shift: (F/2,G/2).
    float disc=0.25-(a*a+q2);
    float dt,dp;
    float D=r*r+a*a;
    if (disc>1e-12) {
        float h=sqrt(disc),rp=0.5+h,rm=(a*a+q2)/rp;
        float lp=log(max(abs(r-rp),1e-30));
        float lm=log(max(abs(r-rm),1e-30));
        dt=((rp*rp+a*a)*lp-(rm*rm+a*a)*lm)/(2.0*h);
        dp=a*(lp-lm)/(2.0*h);
    } else if (disc < -1e-12) {
        float h=sqrt(-disc);
        float angle=atan((r-0.5)/h);
        dt=0.5*log(max(abs(r*r-r+a*a+q2),1e-30))+(0.5-q2)*angle/h;
        dp=a*angle/h;
    } else {
        float z=r-0.5;
        z=(z<0.0?-1.0:1.0)*max(abs(z),1e-30);
        dt=log(abs(z))-(0.5-q2)/z;
        dp=-a/z;
    }
    return vec2(dt,dp+atan(a,max(r,1e-30)));
}

vec2 KN_Reg(KN_Orbit o, float u) {
    float r=KN_Radius(o,u),h=sqrt(KN_H(o,u));
    if (o.simple) {
        // L=0 fallback: directly integrate the regular ingoing branch.
        // Also covers exact extremality and RN without near-coincident poles.
        float P=r*r+o.a*o.a;
        float S=u*h;
        float j=(r*r+o.a*o.a)/(P+S);
        return -2.0/h*vec2((r*r+o.a*o.a)*j-o.a*o.a,o.a*j-o.a)
               -2.0*u*vec2(1.0,o.a/(r*r+o.a*o.a));
    }
    vec2 z=-2.0/h*vec2(r*r+r+1.0-o.q2,o.L);
    z+=2.0*o.resP*(r+o.rp+o.rt-o.A)/(h*o.hroot.x*(h+o.hroot.x));
    z+=2.0*o.resM*(r+o.rm+o.rt-o.A)/(h*o.hroot.y*(h+o.hroot.y));
    return z;
}

float KN_LogRatio(float a,float b) {
    float z=(a-b)/b;
    if (abs(z)<0.03) {
        float w=z/(2.0+z),v=w*w;
        return 2.0*w*(1.0+v*(1.0/3.0+v*(1.0/5.0+v/7.0)));
    }
    return log(a/b);
}

vec2 KN_IntegralBetween(KN_Orbit o,float ua,float ub) {
    if (ua==ub) return vec2(0.0);
    // Short, smooth intervals: integrate directly in u. Avoid reconstructing
    // two almost equal u's via exp(asinh(u)), which spoiled the old local clock.
    float ulo=min(ua,ub),uhi=max(ua,ub);
    float hmid=0.5*(ua+ub), hhalf=0.5*(ub-ua);
    if (uhi-ulo <= 0.12*max(ulo,max(o.mapScale,1e-12))
        && (o.mapCentre==0.0 || abs(hmid-o.mapCentre)>2.0*abs(hhalf))) {
        const vec4 ns=vec4(0.18343464249565,0.52553240991633,0.79666647741363,0.96028985649754);
        const vec4 ws=vec4(0.36268378337836,0.31370664587789,0.22238103445337,0.10122853629038);
        vec2 sum=vec2(0.0);
        for(int j=0;j<4;++j)
            sum+=ws[j]*(KN_Reg(o,hmid-hhalf*ns[j])+KN_Reg(o,hmid+hhalf*ns[j]));
        return hhalf*sum;
    }
    // The regular remainder is even. ua/ub here are NONNEGATIVE.
    float va=KN_Asinh((ua-o.mapCentre)/o.mapScale);
    float vb=KN_Asinh((ub-o.mapCentre)/o.mapScale);
    int panels=int(clamp(ceil(abs(vb-va)/KN_QUAD_V_SPAN),1.0,float(KN_QUAD_MAX_PANELS)));
    const vec4 nodes=vec4(0.18343464249565,0.52553240991633,0.79666647741363,0.96028985649754);
    const vec4 weights=vec4(0.36268378337836,0.31370664587789,0.22238103445337,0.10122853629038);
    vec2 sum=vec2(0.0),comp=vec2(0.0);
    float width=(vb-va)/float(panels);
    for (int j=0;j<KN_QUAD_MAX_PANELS;++j) {
        if (j>=panels) break;
        float mid=va+(float(j)+0.5)*width, halfw=0.5*width;
        for (int n=0;n<4;++n) {
            float v1=mid-halfw*nodes[n],v2=mid+halfw*nodes[n];
            float e1=exp(v1),e2=exp(v2);
            float u1=o.mapCentre+0.5*o.mapScale*(e1-1.0/e1);
            float u2=o.mapCentre+0.5*o.mapScale*(e2-1.0/e2);
            float j1=0.5*o.mapScale*(e1+1.0/e1);
            float j2=0.5*o.mapScale*(e2+1.0/e2);
            vec2 value=halfw*weights[n]*(KN_Reg(o,max(u1,0.0))*j1+KN_Reg(o,max(u2,0.0))*j2);
            vec2 y=value-comp,t=sum+y;comp=(t-sum)-y;sum=t;
        }
    }
    return sum;
}

vec2 KN_J(KN_Orbit o,float u,float d) {
    if (o.simple) {
        if (u>=0.0) return (d-1.0)*KN_HorizonPrimitive(KN_Radius(o,u),o.a,o.q2);
        return -2.0*KN_HorizonPrimitive(o.rt,o.a,o.q2)
             +(d+1.0)*KN_HorizonPrimitive(KN_Radius(o,u),o.a,o.q2);
    }
    vec2 z=vec2(0.0,d*atan(o.a,max(KN_Radius(o,u),1e-30)));
    vec2 pp=o.poleP,pm=o.poleM;
    if (d!=o.sig.x) z+=pp*(d-o.sig.x)*log(max(abs(u-o.uh.x),1e-30));
    if (d!=-o.sig.x)z+=pp*(d+o.sig.x)*log(max(abs(u+o.uh.x),1e-30));
    if (d!=o.sig.y) z+=pm*(d-o.sig.y)*log(max(abs(u-o.uh.y),1e-30));
    if (d!=-o.sig.y)z+=pm*(d+o.sig.y)*log(max(abs(u+o.uh.y),1e-30));
    return z;
}

KN_Orbit KN_MakeOrbit(float a,float q2,float L,int id) {
    KN_Orbit o;
    o.a=a;o.q2=q2;o.L=L;o.k=L-a;o.A=L*L+q2;
    o.gap=sqrt(max(0.0,1.0-4.0*(a*a+q2)));
    o.rp=0.5*(1.0+o.gap);o.rm=(a*a+q2)/o.rp;
    o.enabled=q2>=0.0 && a*a+q2<=0.25 && o.rp<length(FTP_INITIAL_POS);
    o.simple=(L==0.0); // cheaper regular L=0 branch, avoids any pole cancellation
    o.phi0=atan(FTP_INITIAL_POS.x,FTP_INITIAL_POS.z)
           +(id==1?-KN_START_SPREAD:(id==2?KN_START_SPREAD:0.0));
    o.initialI=vec2(0.0);o.initialJ=vec2(0.0);
    o.uh=vec2(0.0);o.sig=vec2(1.0);o.hroot=vec2(1.0);
    o.poleP=vec2(0.0);o.poleM=vec2(0.0);o.resP=vec2(0.0);o.resM=vec2(0.0);
    o.rt=0.0;o.innerDepth=0.0;o.hb=0.0;o.hc=1.0;o.u0=10.0;o.mapCentre=0.0;o.mapScale=1.0;
    if (!o.enabled || (!o.simple && o.gap<2e-5)) {o.enabled=false;return o;}
    if (!KN_Captured(o)) {o.enabled=false;return o;}
    KN_FindTurn(o);
    if (!(o.hc>0.0) || o.rt>=o.rp || o.innerDepth<=0.0) {o.enabled=false;return o;}
    if (!o.simple) {
        o.uh=vec2(sqrt(o.gap+o.innerDepth),sqrt(o.innerDepth));
        vec2 ph=vec2(KN_P(o,o.rp),KN_P(o,o.rm));
        o.sig=sign(ph);
        o.hroot=abs(ph)/o.uh;
        o.poleP=vec2(o.rp*o.rp+a*a,a)/o.gap;
        o.poleM=-vec2(o.rm*o.rm+a*a,a)/o.gap;
        o.resP=o.poleP*ph.x;o.resM=o.poleM*ph.y;
        if (min(o.hroot.x,o.hroot.y)<=1e-15) {o.enabled=false;return o;}
    }
    // Do not integrate 0..u0 just to throw it away in I(u)-I(u0).
    // Incoming queries integrate directly FROM the launch event.
    o.initialI=vec2(0.0);
    o.initialJ=KN_J(o,o.u0,1.0);
    return o;
}

void KN_Init(float a,float q2) {
    if (KN_ready) return;
    KN_ready=true;
    KN_orbits[0]=KN_MakeOrbit(a,q2,0.0,0);
    float disc=0.25-(a*a+q2);
    float rm=KN_orbits[0].rm;
    bool pair=abs(a)>1e-7 && disc>1e-10 && rm>0.0 && q2>=0.0;
    float lc=pair?(rm*rm+a*a)/a:0.0;
    float offset=KN_L_OFFSET*abs(lc);
    for (int id=1;id<3;++id) {
        KN_orbits[id]=KN_MakeOrbit(a,q2,lc+(id==1?-offset:offset),id);
        KN_orbits[id].enabled=KN_orbits[id].enabled && pair;
    }
    for (int id=0;id<3;++id) {
        KN_cacheValid[id]=false;KN_cachedU[id]=0.0;KN_cachedI[id]=vec2(0.0);
        KN_returnReady[id]=false;KN_returnConstant[id]=vec2(0.0);
    }
}

// Stable differences of horizon terms; never subtract nearby large logs.
vec2 KN_HorizonDifference(KN_Orbit o,float r,float r0) {
    float dp=log(max(abs(r-o.rp),1e-30)/max(abs(r0-o.rp),1e-30));
    float dm=log(max(abs(r-o.rm),1e-30)/max(abs(r0-o.rm),1e-30));
    if(o.gap<2e-5) return KN_HorizonPrimitive(r,o.a,o.q2)-KN_HorizonPrimitive(r0,o.a,o.q2);
    return vec2(((o.rp*o.rp+o.a*o.a)*dp-(o.rm*o.rm+o.a*o.a)*dm)/o.gap,
                o.a*(dp-dm)/o.gap+atan(o.a*(r0-r),r*r0+o.a*o.a));
}
vec2 KN_JDifference(KN_Orbit o,float u,float u0,float d) {
    float r=KN_Radius(o,u),r0=KN_Radius(o,u0);
    if(o.simple) {
        float mult=u0>=0.0?d-1.0:d+1.0;
        if(mult==0.0)return vec2(0.0);
        return mult*KN_HorizonDifference(o,r,r0);
    }
    vec2 z=vec2(0.0,d*atan(o.a*(r0-r),r*r0+o.a*o.a));
    if(d!=o.sig.x)z+=o.poleP*(d-o.sig.x)*KN_LogRatio(max(abs(u-o.uh.x),1e-30),max(abs(u0-o.uh.x),1e-30));
    if(d!=-o.sig.x)z+=o.poleP*(d+o.sig.x)*KN_LogRatio(max(abs(u+o.uh.x),1e-30),max(abs(u0+o.uh.x),1e-30));
    if(d!=o.sig.y)z+=o.poleM*(d-o.sig.y)*KN_LogRatio(max(abs(u-o.uh.y),1e-30),max(abs(u0-o.uh.y),1e-30));
    if(d!=-o.sig.y)z+=o.poleM*(d+o.sig.y)*KN_LogRatio(max(abs(u+o.uh.y),1e-30),max(abs(u0+o.uh.y),1e-30));
    return z;
}
vec2 KN_AbsolutePhase(KN_Orbit o,float u,float d) {
    if(u>=0.0) {
        vec2 z=KN_IntegralBetween(o,o.u0,u);
        if(d==1.0)return z+KN_JDifference(o,u,o.u0,d);
        return z+KN_J(o,u,d)-o.initialJ;
    }
    return -KN_IntegralBetween(o,0.0,abs(u))-KN_IntegralBetween(o,0.0,o.u0)
           +KN_J(o,u,d)-o.initialJ;
}
vec2 KN_ReturnConstant(int id) {
    if(!KN_returnReady[id]) {
        KN_Orbit o=KN_orbits[id];
        vec2 I0=KN_IntegralBetween(o,0.0,o.u0);
        vec2 J0=o.simple?KN_HorizonPrimitive(o.rt,o.a,o.q2):o.initialJ;
        KN_returnConstant[id]=-2.0*(I0+J0);
        KN_returnReady[id]=true;
    }
    return KN_returnConstant[id];
}
struct KN_Piece {
    KN_Orbit o;
    float ua,ub,d,anchorU,phaseSign;
    vec2 anchorI;  // PHYSICAL T/azimuth relative to launch at the signed anchor
    float ta,tb;
    vec2 phaseA,phaseB;
    vec2 q0,q1,q2,q3,q4,q5;
    bool fast;
};
vec2 KN_RegularDelta(KN_Piece p,float u) {
    return p.phaseSign*KN_IntegralBetween(p.o,p.anchorU,abs(u));
}
vec2 KN_PhasePolynomial(KN_Piece p,float x) {
    return p.q0+x*(p.q1+x*(p.q2+x*(p.q3+x*(p.q4+x*p.q5))));
}
vec2 KN_RawPiecePhase(KN_Piece p,float u) {
    float anchor=p.phaseSign*p.anchorU;
    return KN_RegularDelta(p,u)+KN_JDifference(p.o,u,anchor,p.d);
}
vec2 KN_PiecePhase(KN_Piece p,float u) {
    if(u==p.ua)return p.phaseA;
    if(u==p.ub)return p.phaseB;
    vec2 I=p.fast?KN_PhasePolynomial(p,(u-p.ua)/(p.ub-p.ua)):KN_RegularDelta(p,u);
    return I+KN_JDifference(p.o,u,p.phaseSign*p.anchorU,p.d);
}

void KN_Velocity(KN_Orbit o,float u,float d,float phi,
                 out vec3 centre,out vec4 U,out float dTdu) {
    float r=KN_Radius(o,u),r2=max(r*r,1e-24),D=r2+o.a*o.a;
    float h=sqrt(KN_H(o,u)),S=u*h;
    float P=KN_P(o,r),delta=KN_Delta(o,r);
    float den=P+d*S;
    float j;
    if (abs(den)>=abs(P-d*S)) j=(r2+o.k*o.k)/den;
    else j=(P-d*S)/((delta<0.0?-1.0:1.0)*max(abs(delta),1e-30));
    float ur=-S/r2;
    float ut=(D*j+d*S+o.a*o.k)/r2;
    float uphi=(o.a*j+o.k+d*o.a*S/D)/r2;
    float rho=sqrt(D),sn=sin(phi),cs=cos(phi);
    centre=vec3(rho*sn,0.0,rho*cs);
    vec3 radial=vec3(sn,0.0,cs)*(r/rho)*ur;
    U=vec4(radial+vec3(centre.z,0.0,-centre.x)*uphi,ut);
    dTdu=-2.0*(D*j+d*S+o.a*o.k)/h;
}

float KN_CompensatedGap(FTP_Curve c,float s,float rh,float r) {
    if (rh<1e-12) return r-rh;
    vec3 v=c.c0.xyz;
    vec3 off=(s*(c.c1+s*(c.c2+s*c.c3))).xyz;
    vec3 w=vec3(1.0,1.0+c.a*c.a/(rh*rh),1.0);
    vec3 sq=v*v;
    vec3 rem=fma(v,v,-sq);
    vec2 p=FTP_TwoSum(sq.x,w.y*sq.y);
    vec2 q=FTP_TwoSum(p.x,sq.z);
    vec2 z=FTP_TwoSum(q.x,-(rh*rh+c.a*c.a));
    float residual=rem.x+w.y*rem.y+rem.z+fma(w.y,sq.y,-w.y*sq.y)
                   +p.y+q.y+z.y;
    float value=z.x+(residual+2.0*dot(w*v,off)+dot(w*off,off));
    vec3 X=v+off;
    float factor=1.0+c.a*c.a*X.y*X.y/max(rh*rh*r*r,1e-30);
    return value/((r+rh)*factor);
}

void KN_RayInChart(FTP_Curve c,float s,float d,out vec4 X,out vec4 tangent) {
    FTP_Native(c,s,X,tangent);
    float nativeD=c.outgoing?-1.0:1.0;
    if (nativeD==d) return;
    float dir=0.5*(d-nativeD);
    float r=KerrSchildRadius(X.xyz,c.a,1.0),D=r*r+c.a*c.a;
    float disc=0.25-(c.a*c.a+c.Q2);
    vec2 f;
    float delta;
    if (disc>1e-12) {
        float gap=2.0*sqrt(disc),rp=0.5*(1.0+gap),rm=(c.a*c.a+c.Q2)/rp;
        float gp=KN_CompensatedGap(c,s,rp,r),gm=KN_CompensatedGap(c,s,rm,r);
        float lp=log(max(abs(gp),1e-30)),lm=log(max(abs(gm),1e-30));
        f=2.0*vec2(((rp*rp+c.a*c.a)*lp-(rm*rm+c.a*c.a)*lm)/gap,
                    c.a*(lp-lm)/gap+atan(c.a,max(r,1e-30)));
        delta=gp*gm;
    } else {
        f=2.0*KN_HorizonPrimitive(r,c.a,c.Q2);
        delta=r*r-r+c.a*c.a+c.Q2;
    }
    float rho4=r*r*r*r+c.a*c.a*X.y*X.y;
    vec3 gradR=vec3(X.x*r*r*r,X.y*r*D,X.z*r*r*r)/max(rho4,1e-30);
    float dr=dot(gradR,tangent.xyz);
    float safeDelta=(delta<0.0?-1.0:1.0)*max(abs(delta),1e-30);
    float fp=2.0*(r-c.Q2)/safeDelta;
    float gp=2.0*c.a*(r-c.Q2)/(safeDelta*D);
    float angle=dir*f.y,cs=cos(angle),sn=sin(angle);
    vec3 pos=vec3(cs*X.x+sn*X.z,X.y,cs*X.z-sn*X.x);
    vec3 vel=vec3(cs*tangent.x+sn*tangent.z,tangent.y,cs*tangent.z-sn*tangent.x);
    vel+=dir*gp*dr*vec3(pos.z,0.0,-pos.x);
    X=vec4(pos,X.w+dir*f.x);
    tangent=vec4(vel,fma(dir*fp,dr,tangent.w));
}

struct KN_Sample {
    vec4 X,tangent,U;
    vec3 q,dq,centre;
    float radius,u;
    bool alive,valid;
};

// The centre radius is already known from the orbit. Recovering it again
// from x^2+z^2-a^2 is badly conditioned near the Kerr ring.
vec3 KN_CentreCov(KN_Orbit o,float u,float d,vec3 pos,out vec3 l,out float f) {
    float r=max(KN_Radius(o,u),1e-12),D=r*r+o.a*o.a;
    float rho=sqrt(D),h=sqrt(KN_H(o,u)),S=u*h,P=KN_P(o,r);
    l=vec3((d*r*pos.x-o.a*pos.z)/D,0.0,(d*r*pos.z+o.a*pos.x)/D);
    f=max((r-o.q2)/(r*r),0.0);
    float den=D*(P+d*S);
    float pr=(d*r*r*o.L*o.L-P*S)/den;
    return (pos/rho)*(pr*rho/r)+vec3(pos.z,0.0,-pos.x)*(o.L/D);
}

// Coframe B with B^T B=g_ij+U_i U_j, for Delta T=0.
// Positive sum-of-squares evaluation remains stable at large Lorentz factors.
mat3 KN_Coframe(vec3 l,float f,vec3 ucov) {
    // Two positive rank-one square-root updates, avoiding catastrophic
    // subtractions in a Cholesky factorization at high Lorentz factors.
    float ll=dot(l,l);
    float beta=f/(sqrt(1.0+f*ll)+1.0);
    mat3 B1=mat3(1.0)+beta*outerProduct(l,l);
    vec3 w=ucov-(beta/(1.0+beta*ll))*l*dot(l,ucov);
    mat3 B2=mat3(1.0)+outerProduct(w,w)/(sqrt(1.0+dot(w,w))+1.0);
    return B2*B1;
}

KN_Sample KN_Evaluate(FTP_Curve c,KN_Piece p,float s) {
    KN_Sample outp;
    KN_RayInChart(c,s,p.d,outp.X,outp.tangent);
    // Solve a LOCAL time difference. Do not recover a small displacement from
    // absolute primitives of order r0^(3/2), then reject their rounding error.
    vec2 time0=FTP_TwoSum(iBlackHoleTime,-p.anchorI.x);
    float target=time0.x+(time0.y+outp.X.w);
    float tmin=min(p.ta,p.tb),tmax=max(p.ta,p.tb);
    outp.alive=target>=tmin && target<=tmax;
    float a=p.ua,b=p.ub;
    bool increasing=p.tb>p.ta;
    // Geometric initial guess: a true hit's centre has nearly this cylindrical
    // radius. This avoids slow time-inversion convergence near the inner horizon.
    float rc2=fma(outp.X.x,outp.X.x,fma(outp.X.z,outp.X.z,-p.o.a*p.o.a));
    float rc=sqrt(max(rc2,0.0));
    float uc=sqrt(max((rc-p.o.rm)+p.o.innerDepth,0.0));
    float u=clamp(p.ua<0.0?-uc:uc,a,b);
    if (!outp.alive) u=abs(target-p.ta)<abs(target-p.tb)?a:b;
    vec2 phase=KN_PiecePhase(p,u);
    float dTdu;
    float phi=p.o.phi0+p.anchorI.y+phase.y;
    KN_Velocity(p.o,u,p.d,phi,outp.centre,outp.U,dTdu);
    float err=phase.x-target;
    float bestU=u,bestError=abs(err);
    float clockTol=max(5e-8,1e-7*max(abs(target),abs(phase.x)));
    if (outp.alive) {
        for (int it=0;it<KN_TIME_ITERS;++it) {
            // Local time error translated to a conservative coordinate displacement.
            if (abs(err)<=clockTol) break;
            if ((err<0.0)==increasing) a=u;else b=u;
            float trial=u-err/dTdu;
            float nextU=(trial>a && trial<b)?trial:0.5*(a+b);
            if(nextU==u)break;
            u=nextU;
            phase=KN_PiecePhase(p,u);
            phi=p.o.phi0+p.anchorI.y+phase.y;
            KN_Velocity(p.o,u,p.d,phi,outp.centre,outp.U,dTdu);
            err=phase.x-target;
            if(abs(err)<bestError){bestError=abs(err);bestU=u;}
        }
        if(u!=bestU){
            u=bestU;phase=KN_PiecePhase(p,u);
            phi=p.o.phi0+p.anchorI.y+phase.y;
            KN_Velocity(p.o,u,p.d,phi,outp.centre,outp.U,dTdu);
            err=phase.x-target;
        }
    }
    outp.u=u;outp.radius=KN_Radius(p.o,u);
    vec3 delta=outp.X.xyz-outp.centre;
    vec3 velocity=outp.alive?outp.U.xyz/outp.U.w:vec3(0.0);
    vec3 relative=outp.tangent.xyz-velocity*outp.tangent.w;
    if (KN_REST_SPHERE) {
        vec3 l;float f;
        vec3 ucov=KN_CentreCov(p.o,u,p.d,outp.centre,l,f);
        mat3 B=KN_Coframe(l,f,ucov);
        outp.q=B*delta;
        // Frame derivative is omitted only in the Newton predictor. Bracketing
        // and all residual evaluations use the full, position-dependent frame.
        outp.dq=B*relative;
    } else {outp.q=delta;outp.dq=relative;}
    outp.valid=!any(isnan(outp.q))&&!any(isinf(outp.q))
             &&!any(isnan(outp.dq))&&!any(isinf(outp.dq))
             &&KN_IsFinite(outp.U.w);
    // A failed time solve must not manufacture an opaque hit.
    // Use the SAME spatial accuracy criterion as the surface solver. The old
    // code stopped on a relative absolute-time tolerance, then invalidated that
    // same solution with a smaller fixed TIME cutoff (not a spatial cutoff).
    // At r~100 it could reject every endpoint although the centre was accurate.
    float speed=length(outp.U.xyz)/max(abs(outp.U.w),1e-20);
    float spatialError=abs(err)*speed;
    float spatialTol=max(5e-6,8e-7*max(length(outp.centre),length(outp.X.xyz)));
    if(outp.alive && spatialError>spatialTol)outp.valid=false;
    return outp;
}

float KN_Tol(KN_Sample p) {
    return max(5e-6,6e-7*max(length(p.centre),length(p.X.xyz)));
}

bool KN_Refine(FTP_Curve c,KN_Piece p,float l,float h,KN_Sample pl,KN_Sample ph,
               float guess,out float hitS,out KN_Sample hit) {
    float fl=dot(pl.q,pl.q)-KN_BALL_RADIUS*KN_BALL_RADIUS;
    float fh=dot(ph.q,ph.q)-KN_BALL_RADIUS*KN_BALL_RADIUS;
    if ((fl>0.0)==(fh>0.0)) return false;
    float s=clamp(guess,l,h);
    hit=pl;hitS=l;
    for (int i=0;i<KN_HIT_ROOT_ITERS;++i) {
        KN_Sample q=KN_Evaluate(c,p,s);
        if (!q.valid) return false;
        float f=dot(q.q,q.q)-KN_BALL_RADIUS*KN_BALL_RADIUS;
        if (abs(length(q.q)-KN_BALL_RADIUS)<=KN_Tol(q)) {hit=q;hitS=s;return q.alive;}
        if ((f>0.0)==(fl>0.0)) {l=s;fl=f;} else {h=s;fh=f;}
        float df=2.0*dot(q.q,q.dq);
        float trial=s-f/df,guard=0.02*(h-l);
        s=(trial>l+guard&&trial<h-guard)?trial:0.5*(l+h);
    }
    return false;
}

bool KN_FirstHit(FTP_Curve c,KN_Piece p,out float hitS,out KN_Sample hit) {
    if ((c.outgoing?-1.0:1.0)==p.d) {
        vec4 b0,b1,b2,b3;FTP_Bezier(c,0.0,1.0,b0,b1,b2,b3);
        float offset=iBlackHoleTime-p.anchorI.x;
        float lo=offset+min(min(b0.w,b1.w),min(b2.w,b3.w));
        float hi=offset+max(max(b0.w,b1.w),max(b2.w,b3.w));
        float pad=2e-6*max(1.0,max(abs(lo),abs(hi)));
        if(hi+pad<min(p.ta,p.tb)||lo-pad>max(p.ta,p.tb))return false;
    }
    float l=0.0,span=1.0;
    KN_Sample pl=KN_Evaluate(c,p,l);
    if (!pl.valid) return false;
    for (int it=0;it<KN_HIT_INTERVALS;++it) {
        float h=min(1.0,l+span);
        if (h<=l) break;
        KN_Sample ph=KN_Evaluate(c,p,h);
        KN_Sample pm=KN_Evaluate(c,p,0.5*(l+h));
        if (!ph.valid||!pm.valid) {span*=0.5;if(span<KN_MIN_SPAN)break;continue;}
        float tol=max(KN_Tol(pl),max(KN_Tol(pm),KN_Tol(ph)));
        float fl=length(pl.q)-KN_BALL_RADIUS;
        if (pl.alive&&abs(fl)<=tol) {hitS=l;hit=pl;return true;}
        // An actually sampled interior witness already brackets a surface.
        // Do not flatten the entire relative curve to micron tolerance first:
        // that wastes the budget at a near-horizon, rapidly changing frame.
        float fm0=length(pm.q)-KN_BALL_RADIUS;
        float fh0=length(ph.q)-KN_BALL_RADIUS;
        if ((fl>0.0)!=(fm0>0.0)) {
            float guess=mix(l,0.5*(l+h),clamp(fl/(fl-fm0),0.0,1.0));
            if(KN_Refine(c,p,l,0.5*(l+h),pl,pm,guess,hitS,hit))return true;
        }
        if ((fm0>0.0)!=(fh0>0.0)) {
            float guess=mix(0.5*(l+h),h,clamp(fm0/(fm0-fh0),0.0,1.0));
            if(KN_Refine(c,p,0.5*(l+h),h,pm,ph,guess,hitS,hit))return true;
        }
        vec3 b1=pl.q+(h-l)*pl.dq/3.0,b2=ph.q-(h-l)*ph.dq/3.0;
        float bend=0.75*max(length(b1-(2.0*pl.q+ph.q)/3.0),length(b2-(pl.q+2.0*ph.q)/3.0));
        vec3 predicted=(pl.q+3.0*b1+3.0*b2+ph.q)*0.125;
        float error=2.0*bend+8.0*length(pm.q-predicted);
        float closest;
        float distance=FTP_SegmentDistance(pl.q,ph.q,closest);
        bool outside=distance>KN_BALL_RADIUS+error+tol;
        bool inside=max(length(pl.q),length(ph.q))+error<KN_BALL_RADIUS-tol;
        if (!outside&&!inside) {
            if (error>2.0*tol&&span>KN_MIN_SPAN) {span*=0.5;continue;}
            float middle=mix(l,h,closest);
            KN_Sample pc=KN_Evaluate(c,p,middle);
            if (!pc.valid) {span*=0.5;continue;}
            float fm=length(pc.q)-KN_BALL_RADIUS,fh=length(ph.q)-KN_BALL_RADIUS;
            float halfChord=sqrt(max(0.0,KN_BALL_RADIUS*KN_BALL_RADIUS-distance*distance));
            float clen=max(length(ph.q-pl.q),1e-20);
            float entry=mix(l,h,clamp(closest-halfChord/clen,0.0,1.0));
            float exitS=mix(l,h,clamp(closest+halfChord/clen,0.0,1.0));
            bool found=false;
            if (fl>0.0&&fm<=0.0)found=KN_Refine(c,p,l,middle,pl,pc,entry,hitS,hit);
            else if(fl>0.0&&fh<=0.0)found=KN_Refine(c,p,l,h,pl,ph,entry,hitS,hit);
            else if(fl<0.0&&fm>=0.0)found=KN_Refine(c,p,l,middle,pl,pc,exitS,hitS,hit);
            else if(fl<0.0&&fh>=0.0)found=KN_Refine(c,p,l,h,pl,ph,exitS,hitS,hit);
            if(found)return true;
            if(pc.alive&&abs(fm)<=tol){hitS=middle;hit=pc;return true;}
            if(ph.alive&&abs(fh)<=tol){hitS=h;hit=ph;return true;}
            if(span>KN_MIN_SPAN&&error>0.25*tol){span*=0.5;continue;}
        }
        l=h;pl=ph;
        if(l>=1.0)break;
        span=min(2.0*span,1.0-l);
    }
    // Empirical curve / phase-fit checks and a bounded budget:
    // NOT a certified interval solver.
    return false;
}

bool KN_MakePiece(int id,float rlo,float rhi,float phaseSign,out KN_Piece p) {
    p.o=KN_orbits[id];
    float rFloor=p.o.rt>0.0?p.o.rt:min(FTP_END_RADIUS,max(1e-6,0.05*p.o.rm));
    rlo=max(rlo,rFloor);rhi=max(rhi,rlo);
    if (rhi<=rlo) return false;
    float ua=sqrt(max((rlo-p.o.rm)+p.o.innerDepth,0.0));
    float ub=sqrt(max((rhi-p.o.rm)+p.o.innerDepth,0.0));
    p.ua=phaseSign>0.0?ua:-ub;p.ub=phaseSign>0.0?ub:-ua;
    float mid=0.5*(p.ua+p.ub);
    p.d=phaseSign*(KN_P(p.o,KN_Radius(p.o,mid))>=0.0?1.0:-1.0);
    p.anchorU=abs(mid);p.phaseSign=phaseSign;
    // An exact query cache, not accumulated integration along a ray.
    float key=abs(mid);
    vec2 incoming;
    if(KN_cacheValid[id]&&KN_cachedU[id]==key)incoming=KN_cachedI[id];
    else incoming=KN_AbsolutePhase(p.o,key,phaseSign*p.d);
    KN_cacheValid[id]=true;KN_cachedU[id]=key;KN_cachedI[id]=incoming;
    p.anchorI=phaseSign>0.0?incoming:KN_ReturnConstant(id)-incoming;
    vec2 y0=KN_RegularDelta(p,p.ua),y1=KN_RegularDelta(p,p.ub);
    float du=p.ub-p.ua;
    vec2 d0=du*KN_Reg(p.o,abs(p.ua));
    vec2 dm=du*KN_Reg(p.o,p.anchorU);
    vec2 d1=du*KN_Reg(p.o,abs(p.ub));
    // Quintic Hermite primitive: endpoint/midpoint values and derivatives.
    // Poles are NEVER fitted; their exact log differences remain outside it.
    vec2 slope=y1-y0;
    vec2 a0=d0-slope,am=dm-slope,a1=d1-slope,ym=-0.5*(y0+y1);
    p.q0=y0;p.q1=d0;
    p.q2=-6.0*a0-a1-8.0*am+16.0*ym;
    p.q3=13.0*a0+5.0*a1+32.0*am-32.0*ym;
    p.q4=-12.0*a0-8.0*a1-40.0*am+16.0*ym;
    p.q5=4.0*a0+4.0*a1+16.0*am;
    vec2 err=max(abs(KN_PhasePolynomial(p,0.25)-KN_RegularDelta(p,mix(p.ua,p.ub,0.25))),
                 abs(KN_PhasePolynomial(p,0.75)-KN_RegularDelta(p,mix(p.ua,p.ub,0.75))));
    float rho=sqrt(rhi*rhi+p.o.a*p.o.a);
    p.fast=max(err.x,rho*err.y)<max(1e-6,1e-7*rho);
    p.phaseA=y0+KN_JDifference(p.o,p.ua,mid,p.d);
    p.phaseB=y1+KN_JDifference(p.o,p.ub,mid,p.d);
    p.ta=p.phaseA.x;p.tb=p.phaseB.x;
    return KN_IsFinite(p.ta)&&KN_IsFinite(p.tb)&&abs(p.tb-p.ta)>1e-12;
}

// In the weak exterior use analytic ENVELOPES before any orbit quadrature.
// This is a local object broad phase, NOT a change to horizon/shadow culling.
// For r >= 2A, R >= r^3(1-A/rmin) and R <= r^3(1+k^2/rmin^2).
// These inequalities bound the absolute azimuth derivative and dt/dr.
bool KN_OuterBroadMiss(FTP_Curve c,vec4 b0,vec4 b1,vec4 b2,vec4 b3,
                       KN_Orbit o,float rlo,float rhi,float phaseSign,vec2 reflection) {
    float launch=length(FTP_INITIAL_POS),rr=min(rlo,launch);
    float limit=max(4.0,max(2.0*o.A,max(abs(o.k),sqrt(2.0*abs(o.a*o.k)))));
    if(rr<limit)return false;
    float inv=1.0/rr,ab=abs(o.a*o.k)*inv*inv;
    float smin=sqrt(max(1.0-o.A*inv,0.01));
    float smax=sqrt(1.0+o.k*o.k*inv*inv);
    float jmax=(1.0+o.k*o.k*inv*inv)/(1.0-ab);
    float jmin=1.0/(1.0+ab+smax*sqrt(inv));
    float coefficient=(abs(o.a)*jmax+abs(o.k))/smin;
    float angle=2.0*coefficient*max(abs(inversesqrt(rlo)-inversesqrt(launch)),
                                  abs(inversesqrt(rhi)-inversesqrt(launch)))
               +abs(o.a)*max(abs(1.0/rlo-1.0/launch),abs(1.0/rhi-1.0/launch));
    // Native Outgoing angle differs by G(r), with G(infinity)=0 and
    // |G(r)| <= |a|/(r-r+)^2 in this exterior region.
    bool otherChart=c.outgoing!=(phaseSign<0.0);
    if(otherChart)angle+=abs(o.a)/((rlo-o.rp)*(rlo-o.rp));
    angle+=2e-5;
    if(angle<1.40) {
        vec2 axis=vec2(sin(o.phi0+reflection.y),cos(o.phi0+reflection.y));
        vec2 side=vec2(axis.y,-axis.x);
        float slope=tan(angle),pad=KN_BALL_RADIUS*(1.0+slope)+2e-5*rhi;
        vec2 n=side-slope*axis;
        float low=min(min(dot(n,b0.xz),dot(n,b1.xz)),min(dot(n,b2.xz),dot(n,b3.xz)));
        if(low>pad)return true;
        n=-side-slope*axis;
        low=min(min(dot(n,b0.xz),dot(n,b1.xz)),min(dot(n,b2.xz),dot(n,b3.xz)));
        if(low>pad)return true;
        float hi=max(max(dot(axis,b0.xz),dot(axis,b1.xz)),max(dot(axis,b2.xz),dot(axis,b3.xz)));
        if(hi< -KN_BALL_RADIUS)return true;
    }
    float cmn=max(0.0,jmin-ab)/smax;
    float cmx=((1.0+o.a*o.a*inv*inv)*jmax+ab)/smin;
    vec2 radii=vec2(rlo,rhi);
    vec2 dr=vec2(launch)-radii;
    vec2 integ=(2.0/3.0)*(vec2(launch*sqrt(launch))-radii*sqrt(radii));
    vec2 lower=min(dr+cmn*integ,dr+cmx*integ);
    vec2 upper=max(dr+cmn*integ,dr+cmx*integ);
    float tlo=min(lower.x,lower.y),thi=max(upper.x,upper.y);
    if(phaseSign<0.0){float oldlo=tlo;tlo=reflection.x-thi;thi=reflection.x-oldlo;}
    float qlo=min(min(b0.w,b1.w),min(b2.w,b3.w));
    float qhi=max(max(b0.w,b1.w),max(b2.w,b3.w));
    if(otherChart){
        // For a hit, |y|<=R, and r<=sqrt(rho^2+y^2).
        float rupper=sqrt(rhi*rhi+o.a*o.a+KN_BALL_RADIUS*KN_BALL_RADIUS);
        float flo=2.0*KN_HorizonPrimitive(rlo,o.a,o.q2).x;
        float fhi=2.0*KN_HorizonPrimitive(rupper,o.a,o.q2).x;
        qlo+=phaseSign>0.0?flo:-fhi;
        qhi+=phaseSign>0.0?fhi:-flo;
    }
    qlo+=iBlackHoleTime;qhi+=iBlackHoleTime;
    float pad=8e-6*max(1.0,max(max(abs(qlo),abs(qhi)),max(abs(tlo),abs(thi))));
    return qhi+pad<tlo || qlo-pad>thi;
}

vec4 KN_Draw(FTP_Curve c,vec4 BaseColor,float dlambda) {
    vec4 b0,b1,b2,b3;
    FTP_Bezier(c,0.0,1.0,b0,b1,b2,b3);
    float ymin=min(min(b0.y,b1.y),min(b2.y,b3.y));
    float ymax=max(max(b0.y,b1.y),max(b2.y,b3.y));
    if(ymin>KN_BALL_RADIUS||ymax< -KN_BALL_RADIUS)return BaseColor;
    // This bound is invariant under the In/Out azimuthal coordinate rotation.
    float unused;
    vec3 q0=vec3(b0.x,0.0,b0.z),q1=vec3(b1.x,0.0,b1.z);
    vec3 q2=vec3(b2.x,0.0,b2.z),q3=vec3(b3.x,0.0,b3.z);
    float bend=0.75*max(length(q1-(2.0*q0+q3)/3.0),length(q2-(q0+2.0*q3)/3.0));
    float boundPad=KN_BALL_RADIUS+max(2e-5,8e-7*max(length(q0),length(q3)));
    float rholo=max(0.0,FTP_SegmentDistance(q0,q3,unused)-bend-boundPad);
    float rhohi=max(max(length(q0),length(q1)),max(length(q2),length(q3)))+boundPad;
    if(rhohi<abs(c.a))return BaseColor;
    float rlo=sqrt(max(0.0,rholo*rholo-c.a*c.a));
    float rhi=sqrt(max(0.0,rhohi*rhohi-c.a*c.a));
    KN_Init(c.a,c.Q2);
    float best=2.0;int bestID=-1;KN_Sample bestHit;float bestD=1.0;
    for(int id=0;id<3;++id) {
        KN_Orbit o=KN_orbits[id];
        if(!o.enabled||rhi<o.rt)continue;
        float turnSplit=sqrt(max(0.0,o.a*o.k));
        bool split=turnSplit>max(rlo,o.rt)&&turnSplit<rhi;
        for(int branch=0;branch<2;++branch) {
            if(branch==1&&(!KN_SHOW_RETURN||o.rt<=0.0))continue; // ring is not a bounce
            float sg=branch==0?1.0:-1.0;
            vec2 reflection=branch==0?vec2(0.0):KN_ReturnConstant(id);
            if(KN_OuterBroadMiss(c,b0,b1,b2,b3,o,rlo,rhi,sg,reflection))continue;
            for(int part=0;part<2;++part) {
                if(part==1&&!split)break;
                float a=part==0?rlo:turnSplit;
                float b=(part==0&&split)?turnSplit:rhi;
                KN_Piece p;
                if(!KN_MakePiece(id,a,b,sg,p))continue;
                float s;KN_Sample hit;
                if(KN_FirstHit(c,p,s,hit)&&s<best) {
                    if(iWhitehole==0 && hit.tangent.w*sign(dlambda)*sign(hit.U.w)<0.0)continue;
                    best=s;bestID=id;bestHit=hit;bestD=p.d;
                }
            }
        }
    }
    if(bestID<0)return BaseColor;
    vec3 n=normalize(bestHit.q);
    float px=(abs(n.x)+abs(n.y)<1e-12)?1e-12:n.x;
    float checker=mod(floor(atan(n.y,px)*8.0)+floor(asin(clamp(n.z,-1.0,1.0))*8.0),2.0);
    // Different base hues identify L=0 / numeric-L-below / numeric-L-above.
    vec3 tint=bestID==0?vec3(0.90,0.90,0.95):(bestID==1?vec3(0.12,0.80,1.0):vec3(1.0,0.35,0.08));
    vec3 color=tint*(0.40+0.60*(step(0.0,n)*0.8+0.2))*(checker>0.5?1.0:0.12);
    KerrGeometry gh;
    ComputeGeometryScalars(bestHit.X.xyz,c.a,c.Q2,1.0,1.0,bestD<0.0,gh);
    // While Shift=1 only the energy SIGN is required. In a temporal KS chart,
    // future/past orientation gives that sign without subtracting boosted terms.
    float energy=(1.0+gh.f>0.0)
        ?bestHit.tangent.w*sign(dlambda)*sign(bestHit.U.w)
        :-dot(LowerIndex(bestHit.tangent,gh),bestHit.U)*sign(dlambda);
    if(energy<0.0) {
        if(iWhitehole==0)return BaseColor;
        color=vec3(max(max(color.r,color.g),color.b)+min(min(color.r,color.g),color.b))-color;
    }
    // Opaque surface: deliberately independent of coordinate step length.
    return vec4(BaseColor.rgb+color*(1.0-BaseColor.a),1.0);
}

vec4 DrawFallingTestParticle(vec4 BaseColor,vec4 RayPos,vec4 LastRayPos,
                             vec4 P_cov,vec4 LastP_cov,float PhysicalSpinA,
                             float PhysicalQ2,bool isoutgoing,float EndStepSign,float dlambda) {
    if(PhysicalSpinA==0.0&&PhysicalQ2==0.0)
        return FTP_DrawSchwarzschild(BaseColor,RayPos,LastRayPos,P_cov,LastP_cov,
                                    PhysicalSpinA,PhysicalQ2,isoutgoing,EndStepSign,dlambda);
    if(BaseColor.a>0.99||abs(dlambda)<1e-30||EndStepSign<=0.0)return BaseColor;
    KerrGeometry g0,g1;
    ComputeGeometryScalars(LastRayPos.xyz,PhysicalSpinA,PhysicalQ2,1.0,EndStepSign,isoutgoing,g0);
    ComputeGeometryScalars(RayPos.xyz,PhysicalSpinA,PhysicalQ2,1.0,EndStepSign,isoutgoing,g1);
    vec4 T0=dlambda*RaiseIndex(LastP_cov,g0),T1=dlambda*RaiseIndex(P_cov,g1);
    vec4 delta=RayPos-LastRayPos;
    FTP_Curve c;
    c.c0=LastRayPos;c.c1=T0;c.c2=3.0*delta-2.0*T0-T1;c.c3=T0+T1-2.0*delta;
    c.a=PhysicalSpinA;c.Q2=PhysicalQ2;c.signR=EndStepSign;c.outgoing=isoutgoing;
    return KN_Draw(c,BaseColor,dlambda);
}

// =============================================================================
// SECTION7: KN阴影计算
// =============================================================================

bool IsAccretionDiskVisible(float InterR, float OuterR, float Thin, float Hopper, float Bright, float Dark)
{
    if(iUseImageDisk==0){
    if (InterR >= OuterR) return false;
    if (Thin <= 0.0 && Hopper == 0.0) return false;
    if (Bright <= 0.0 && Dark < 0.0) return false;
    }else{
    if (InterR >= OuterR) return false;
    if (Bright <= 0.0 && Dark < 0.0) return false;
    }
    return true;
}

bool IsJetVisible(float AccretionRate, float JetBright)
{
    if (AccretionRate < 1e-2) return false;
    if (JetBright <= 0.0) return false;
    return true;
}

// 有视界时，赤道顺行/逆行临界光子轨道。
float EquatorialPhotonRadius(float M, float Q2, float a, bool Retrograde) {
    float Discriminant = M * M - (a * a + Q2);
    if (Discriminant == 0.0) return Retrograde ? 2.0 * (M + a) : max(M, 2.0 * (M - a));
    float LowerR = M + sqrt(max(0.0, Discriminant));
    float UpperR = 0.5 * (3.0 * M + sqrt(max(0.0, 9.0 * M * M - 8.0 * Q2)));
    if (a == 0.0) return UpperR;
    if (Retrograde) UpperR += 2.0 * a;
    float SpinTerm = Retrograde ? -a : a;
    float r = UpperR;
    // 将牛顿迭代限制在外视界之外，负 Q2 时也不会落到另一支根。
    for (int i = 0; i < 12; ++i) {
        float u = sqrt(max(M * r - Q2, 1e-20));
        float f = r * r - 3.0 * M * r + 2.0 * Q2 + 2.0 * SpinTerm * u;
        if (f > 0.0) UpperR = r; else LowerR = r;
        float df = 2.0 * r - 3.0 * M + SpinTerm * M / u;
        if (abs(f) < 1e-7 * (r * r + M * M + abs(Q2))) break;
        float TrialR = r - f / df;
        r = (TrialR > LowerR && TrialR < UpperR) ? TrialR : 0.5 * (LowerR + UpperR);
    }
    return r;
}

// [MOD] KS 四动量给出的径向势；Dr>0 表示沿反向仿射步向内追踪。
// Carter 组合写成平方和，避免极轴除法及两个大数相减。
vec4 ShadowRadialPotential(vec3 X, vec4 P, float r, float a, float q)
{
    float E = -P.w;
    vec3 axes = vec3(sqrt(r*r+a*a), r, sqrt(r*r+a*a));
    vec3 n = X/axes;
    vec3 J = cross(n, P.xyz*axes);
    float L = J.y;
    vec3 carter = J-a*E*(vec3(0.0, 1.0, 0.0)-n.y*n);
    float K = dot(carter, carter);
    float Q = K-(L-a*E)*(L-a*E);
    return vec4(E*E, 2.0*a*E*(a*E-L)-K, 2.0*CONST_M*K, -a*a*Q-q*K);
}

bool ShadowCaptured(vec3 X, vec4 P, float r, float Dr, float a, float q, float horizon)
{
    const float margin = 0.0001;
    float E = -P.w;
    if (abs(E)<1e-7 || r<=horizon || r*r+a*a>=10000.0) return false;
    if (a==0.0)
    {
        float rp = 0.5*(3.0*CONST_M+sqrt(9.0*CONST_M*CONST_M-8.0*q));
        if (Dr>0.0 && r<rp*(1.0-margin)) return true;
        vec3 J = cross(X, P.xyz);
        float vc = (rp*rp-2.0*CONST_M*rp+q)/(rp*rp*rp*rp);
        float potential = dot(J,J)*vc;
        float gap = E*E-potential;
        float tolerance = margin*(E*E+abs(potential));
        if (gap < -tolerance && r<rp && rp<100.0) return true;
        return gap>tolerance && Dr>0.0;
    }
    vec4 c = ShadowRadialPotential(X, P, r, a, q);
    float rt = 3.0*CONST_M, rt2 = rt*rt;
    if (r>rt && (c.x*rt2+c.y)*rt2+c.z*rt+c.w<0.0) return false;
    float p = c.y/(2.0*c.x);
    if (p>=0.0) return Dr>0.0;
    float t = sqrt(-p/3.0);
    float z = -c.z/(8.0*c.x*t*t*t);
    if (z<=-1.0) return Dr>0.0;
    float rm = 2.0*t*cos(acos(clamp(z,-1.0,1.0))/3.0);
    if (rm<=horizon || (Dr>0.0 && r<rm*(1.0-margin))) return Dr>0.0;
    float rm2 = rm*rm;
    float value = (c.x*rm2+c.y)*rm2+c.z*rm+c.w;
    float tolerance = margin*(c.x*rm2*rm2+abs(c.y)*rm2+c.z*rm+abs(c.w));
    if (value>tolerance) return Dr>0.0;
    // 向外的束缚光线必须在完整度规内转向，才能排除远场 fade 的影响。
    return value < -tolerance && r<rm && rm2+a*a<10000.0;
}

float ShadowMatterInnerRadius(float a, bool hasDisk, bool hasJet)
{
    float inner = 1e20;
    if (hasDisk) inner = max(0.0, iInterRadiusRs);
    // 贴图盘的孔洞和喷流壳以柱半径定义，需换成 KS 半径下界。
    if (iUseImageDisk!=0)
        inner = min(inner, sqrt(max(0.0, iInterRadiusRs*iInterRadiusRs-a*a)));
    if (hasJet)
        inner = min(inner, sqrt(max(0.0, 0.49*iInterRadiusRs*iInterRadiusRs-a*a)));
    return inner;
}


// =============================================================================
// SECTION8: main
// =============================================================================

// 沿 RK 光路的弦段逐格求交；平直区使用同一求交器，接点采用半开区间。
// 图案统一使用场景时间，不计算光行时；频移按静止发射体计算。
// 静止四速不存在的区域不发光。
void TraceRainSegment(inout vec4 result, vec4 start, vec4 finish, float pathStart,
                      float energy, float universeSign, int universeOffset,
                      float spin, float charge, float boundary) {
    if (!RainSheet(universeSign) || result.a>0.99 || pathStart>=RAIN_DISTANCE_RS) return;
    float segmentLength = length(finish.xyz-start.xyz);
    float limit = min(segmentLength, max(0.0, RAIN_DISTANCE_RS-pathStart));
    if (limit<=1e-7) return;
    float scale = max(RAIN_SCALE_RS,1e-4);
    float angle = float((iInWhichUniverse-universeOffset+9)%3)*(2.0*kPi/3.0);
    mat2 turn = mat2(cos(angle),-sin(angle),sin(angle),cos(angle));
    vec3 ro = start.xyz;
    vec3 rd = (finish.xyz-start.xyz)/segmentLength;
    ro.xz = turn*ro.xz; rd.xz = turn*rd.xz;
    ro = ro.xzy/scale; rd = rd.xzy;
    ro.xy += vec2(1.2); // 两条长廊的交叉中心位于黑洞。
    float lengthInCells = limit/scale;
    float horizontal = length(rd.xy);
    if (horizontal<1e-7) return; // 沿字条平面竖直观察时没有迎光面积。
    vec2 across = rd.xy/horizontal;
    float patternTime = (iGameTime+1.0)*RAIN_SPEED;
    ivec2 cell = ivec2(floor(ro.xy/1.2));
    ivec2 stepCell = ivec2(sign(rd.xy));
    vec2 delta = 1.2/max(abs(rd.xy),vec2(1e-20));
    vec2 next = (vec2(cell)+step(vec2(0.0),rd.xy))*1.2;
    next = (next-ro.xy)/vec2(abs(rd.x)<1e-20?1e-20:rd.x,abs(rd.y)<1e-20?1e-20:rd.y);
    if (abs(rd.x)<1e-20) next.x=1e30;
    if (abs(rd.y)<1e-20) next.y=1e30;
    float enter = 0.0;
    while (enter<lengthInCells) {
        if (!(result.a<=0.99)) break;
        float leave = min(lengthInCells,min(next.x,next.y));
        ivec2 block = ivec2(mod(vec2(cell),10.0));
        if (block.x>=2 && block.y>=2 && (block.x>=3 || block.y>=3)) {
            uint columnSeed = RainSeed(ivec3(cell,0));
            float h = RainRandom(columnSeed).x;
            float speed = 0.5+h+h*h+3.0*pow(h,16.0);
            // 将整格偏移留在整数中，避免“大位移 + 小字符坐标”相消。
            float phase = (h*11.0-patternTime*speed)/0.15;
            int charOffset = int(floor(phase));
            int cellOffset = charOffset/40;
            int remainder = charOffset%40;
            if (remainder<0) {remainder+=40;cellOffset-=1;}
            float localZ = ro.z-float(remainder)*0.15;
            float zSlope = rd.z;
            float z0 = localZ+zSlope*enter;
            float z1 = localZ+zSlope*leave;
            int first = int(floor((min(z0,z1)-0.15)/6.0));
            int last = int(floor((max(z0,z1)+0.15)/6.0));
            int zStep = zSlope>=0.0?1:-1;
            int zCell = zStep>0?first:last;
            for (int j=0; j<=last-first; ++j, zCell+=zStep) {
                uint stripSeed = RainSeed(ivec3(cell,zCell-cellOffset));
                vec4 random = RainRandom(stripSeed);
                float count = 7.0+33.0*random.w;
                float stripLength = count*0.15;
                vec2 target = vec2(cell)*1.2+0.05+random.xy*1.1;
                vec2 relative = target-ro.xy;
                float hit = dot(relative,across)/horizontal;
                float u = (relative.x*across.y-relative.y*across.x)/0.05;
                if (hit<enter || hit>=leave || abs(u)>=1.0) continue;
                float height = localZ+rd.z*hit
                             - float(zCell)*6.0-random.z*(6.0-stripLength);
                if (height<0.0 || height>=stripLength) continue;
                float c = floor(height/0.15);
                uint glyphSeed = RainHash(stripSeed ^ RainHash(uint(int(c)+charOffset)));
                vec4 glyphRandom = RainRandom(glyphSeed);
                if (glyphRandom.x<0.1 && c!=0.0) continue;
                float frequency = c==0.0?5.0:random.z+random.w*random.w*4.0*pow(glyphRandom.y,4.0);
                uint event = uint(int(floor(patternTime*frequency)));
                float alpha = RainRune(vec2(u*0.5+0.5,fract(height/0.15)),
                                       RainHash(glyphSeed ^ RainHash(event)), max(1.0,3.0-c*0.5)*0.2);
                alpha = clamp(alpha*clamp((count-0.5-c)*0.5,0.0,1.0),0.0,1.0);
                if (alpha<=0.0) continue;
                float distanceAlongRay = pathStart+hit*scale;
                alpha *= 1.0-smoothstep(0.75*RAIN_DISTANCE_RS,RAIN_DISTANCE_RS,distanceAlongRay);
                vec3 color = (c==0.0?vec3(0.67,1.0,0.82):vec3(0.25,0.8,0.4))
                           / (1.0+pow(0.06*distanceAlongRay/scale,2.0));
#if ANTIVERSE_RAIN_3D == 1
                vec3 position = mix(start.xyz,finish.xyz,hit*scale/segmentLength);
                float fade = CubicInterpolate(clamp(1.0-(length(position)-100.0)/(boundary-100.0),0.0,1.0));
                KerrGeometry local;
                ComputeGeometryScalars(position,spin,charge,fade,universeSign,false,local);
                if (local.f>=1.0) continue;
                float shift = clamp(sqrt(1.0-local.f)/max(abs(energy),1e-14),1.0/iBackShiftMax,iBackShiftMax);
                color = iBackgroundBrightmut*ShiftBackgroundColor(color,shift,true)*pow(shift,4.0);
#endif
                vec4 contribution = (1.0-result.a)*alpha*vec4(color,1.0);
                result += contribution;
#if iPolarization != 0 && ANTIVERSE_RAIN_3D == 1
                rainRadiance += contribution.rgb;
#endif
            }
        }
        if (next.x<next.y) {cell.x+=stepCell.x;next.x+=delta.x;}
        else {cell.y+=stepCell.y;next.y+=delta.y;}
        enter=leave;
    }
}

#if ANTIVERSE_RAIN_3D == 0
vec3 SampleInfiniteRain(vec3 direction) {
    vec4 result=vec4(0.0);
    float rainSign=iBlackHoleMassSol<0.0?1.0:-1.0;
    // 方向已按所在宇宙旋转；固定原点消除相机平移产生的视差。
    TraceRainSegment(result,vec4(0.0),vec4(normalize(direction)*RAIN_DISTANCE_RS,0.0),
                     0.0,1.0,rainSign,iInWhichUniverse,0.0,0.0,501.0);
    return result.rgb;
}
#endif


struct TraceResult {
    vec3  EscapeDir;      // 最终逸出方向 (World Space)
    float FreqShift;      // 频移 (E_emit / E_obs)
    float Status;         // 0=Stop, 1=Sky, 2=Antiverse,3=不透明体积,4=光来自上个宇宙（出白洞）,5=光来自上个宇宙的antiverse
    vec4  AccumColor;     // 体积光颜色 (吸积盘+喷流)
    float CurrentSign;    // 最终宇宙符号
};

#if SHADOW_CULL_DEBUG != 0
vec3 shadowCullDebugColor = vec3(0.0);
#endif

TraceResult TraceRay(vec2 FragUv, vec2 Resolution, int PrepassSteps, sampler2D diskTexture)
{
    TraceResult res;
    res.EscapeDir = vec3(0.0);
    res.FreqShift = 0.0;
    res.Status    = 0.0; // Default: Stop
    res.AccumColor = vec4(0.0);
#if iPolarization != 0
    rainRadiance = vec3(0.0);
#endif

#if SHADOW_CULL_DEBUG != 0
    shadowCullDebugColor = vec3(0.0);
#endif
    bool bShadowTerminated = false;
    int shadowState = 0; // 0=等待完整度规，1=继续追踪，2=捕获
    bool hasShadowDisk = IsAccretionDiskVisible(iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper, iBrightmut, iDarkmut);
    bool hasShadowJet = IsJetVisible(iAccretionRate, iJetBrightmut);

    // 使用 Shadertoy 的底部原点画布坐标。
    float Fov = tan(iFovRadians / 2.0);
    vec2 Jitter = 0.5*vec2(RandomStep(FragUv, fract(iTraceTime * 1.0 + 0.5)), RandomStep(FragUv, fract(iTraceTime * 1.0))) / Resolution;
    vec3 ViewDirLocal = FragUvToDir(FragUv +  Jitter, Fov, Resolution); 

    // -------------------------------------------------------------------------
    // 物理常数与黑洞参数
    // -------------------------------------------------------------------------
    // 吸积盘相关参量
    float iSpinclamp = clamp(iSpin, -0.99, 0.99);
    float a2 = iSpinclamp * iSpinclamp;
    float abs_a = abs(iSpinclamp);
    float common_term = pow(1.0 - a2, 1.0/3.0);
    float Z1 = 1.0 + common_term * (pow(1.0 + abs_a, 1.0/3.0) + pow(1.0 - abs_a, 1.0/3.0));
    float Z2 = sqrt(3.0 * a2 + Z1 * Z1);
    float root_term = sqrt(max(0.0, (3.0 - Z1) * (3.0 + Z1 + 2.0 * Z2))); 
    float Rms_M = 3.0 + Z2 - (sign(iSpinclamp) * root_term); 
    float RmsRatio = Rms_M / 2.0; 
    float AccretionEffective = sqrt(max(0.001, 1.0 - (2.0 / 3.0) / Rms_M));

    const float kPhysicsFactor = 1.52491e30; 
    float DiskArgument = kPhysicsFactor / iBlackHoleMassSol * (iMu / AccretionEffective) * (iAccretionRate);
    float PeakTemperature = pow(DiskArgument * 0.05665278, 0.25);

    // 自旋/电荷 量纲化
    float PhysicalSpinA = iSpin * CONST_M;  
    float PhysicalQ2     = iQ2 * CONST_M * CONST_M; 
    
    // 视界位置
    float HorizonDiscrim = 0.25 - (PhysicalSpinA * PhysicalSpinA + PhysicalQ2);
    vec2 HorizonRadii = KerrHorizonRadii(PhysicalSpinA, PhysicalQ2);
    float EventHorizonR = HorizonRadii.x;
    float InnerHorizonR = HorizonRadii.y;
    bool  bIsNakedSingularity = HorizonDiscrim < 0.0;

    // 包围球
    float RaymarchingBoundary = max(max(iOuterRadiusRs + 1.0, 501.0),iSpin*2.0);
    float ShiftMax = 1.0; //吸积盘亮度最大值
    float CurrentUniverseSign = iUniverseSign;
    if (iBlackHoleMassSol<0.0)
    {
        CurrentUniverseSign=-CurrentUniverseSign;
    }

    // -------------------------------------------------------------------------
    // 相机系统与坐标变换
    // -------------------------------------------------------------------------
    // World Space
    vec3 CamToBHVecVisual = (iInverseCamRot * vec4(iBlackHoleRelativePosRs.xyz, 0.0)).xyz;
    vec3 RayPosWorld = -CamToBHVecVisual; 
    vec3 DiskNormalWorld = normalize((iInverseCamRot * vec4(iBlackHoleRelativeDiskNormal.xyz, 0.0)).xyz);
    vec3 DiskTangentWorld = normalize((iInverseCamRot * vec4(iBlackHoleRelativeDiskTangen.xyz, 0.0)).xyz);
    
    vec3 BH_Y = normalize(DiskNormalWorld);             
    vec3 BH_X = normalize(DiskTangentWorld);            
    BH_X = normalize(BH_X - dot(BH_X, BH_Y) * BH_Y);
    vec3 BH_Z = normalize(cross(BH_X, BH_Y));           
    mat3 LocalToWorldRot = mat3(BH_X, BH_Y, BH_Z);
    mat3 WorldToLocalRot = transpose(LocalToWorldRot);
    
    vec3 RayPosLocal;
    vec3 RayDirWorld_Geo;

    if (iObserverMode == -1) {
        // 测地线模式下，坐标已在正确的局域 KS 系，且射线仅需视锥向量
        RayPosLocal = iBlackHoleRelativePosRs.xyz; 
        // 热折射等空间逻辑需要真实的 KS 空间方向。
        RayDirWorld_Geo = normalize((iInverseCamRot * vec4(ViewDirLocal, 0.0)).xyz);
    } else {
        RayPosLocal = WorldToLocalRot * RayPosWorld;
        RayDirWorld_Geo = WorldToLocalRot * normalize((iInverseCamRot * vec4(ViewDirLocal, 0.0)).xyz);
    }

    vec4 Result = vec4(0.0);
    float rainPathLength = 0.0;
    bool bShouldContinueMarchRay = true;
    bool bWaitCalBack = false;
    float DistanceToBlackHole = length(RayPosLocal);
    

    vec4 X = vec4(0.0);

    if (DistanceToBlackHole > RaymarchingBoundary && !RainVolumeSheet(CurrentUniverseSign)) //跳过与包围盒间空隙
    {
        vec3 O = RayPosLocal; vec3 D = RayDirWorld_Geo; float r = RaymarchingBoundary - 1.0; 
        float b = dot(O, D); float c = dot(O, O) - r * r; float delta = b * b - c; 
        if (delta < 0.0) { 
            bShouldContinueMarchRay = false; 
            bWaitCalBack = true; 
        } 
        else {
            float tEnter = -b - sqrt(delta); 
            if (tEnter > 0.0) {RayPosLocal = O + D * tEnter;X.w-=tEnter;}
            else if (-b + sqrt(delta) <= 0.0) { 
                bShouldContinueMarchRay = false; 
                bWaitCalBack = true; 
            }
        }
    }


    rainPathLength = -X.w;
    X.xyz = RayPosLocal;

    vec4 P_cov = vec4(0.0,0.0,0.0,-1.0);

    float E_conserved = 1.0;
    vec3 RayDir = RayDirWorld_Geo;
    vec3 LastDir = RayDir;
    vec3 LastPos = RayPosLocal;
    float GravityFade = CubicInterpolate(max(min(1.0 - (length(RayPosLocal) - 100.0) / (RaymarchingBoundary - 100.0), 1.0), 0.0));
    
    
    
    if (iEnableHeatHaze == 1 &&  iInWhichUniverse==0 && CurrentUniverseSign>0.0)//热折射
    {
        // 1. 坐标与参数准备 (Rg 空间)
        vec3 pos_Rg_Start = X.xyz; 
        vec3 rayDirNorm = normalize(RayDir);

        float totalProbeDist = float(HAZE_PROBE_STEPS) * HAZE_STEP_SIZE;
        
        // [适配] 使用 iTraceTime，取模防止噪声溢出
        float hazeTime = mod(iBlackHoleTime, 1000.0); 

        if(iDEBUG==1)
        {
            float debugAccum = 0.0;
            float debugStep = 1.0; 
            vec3 debugPos = pos_Rg_Start;
            
            float rotSpeedBase = 100.0 * HAZE_ROT_SPEED;
            float jetSpeedBase = 50.0 * HAZE_FLOW_SPEED;
            
            float ReferenceOmega = GetKeplerianAngularVelocity(6.0, 1.0, PhysicalSpinA, PhysicalQ2);
            float AdaptiveFrequency = abs(ReferenceOmega * rotSpeedBase) / (2.0 * kPi * 5.14);
            AdaptiveFrequency = max(AdaptiveFrequency, 0.1);
            float flowTime = hazeTime * AdaptiveFrequency;

            float phase1 = fract(flowTime); float phase2 = fract(flowTime + 0.5);
            float weight1 = 1.0 - abs(2.0 * phase1 - 1.0); float weight2 = 1.0 - abs(2.0 * phase2 - 1.0);
            float t_offset1 = phase1 - 0.5; float t_offset2 = phase2 - 0.5;
            
            float VerticalDrift1 = t_offset1 * 1.0; 
            float VerticalDrift2 = t_offset2 * 1.0;

            bool doLayer1 = weight1 > 0.05;
            bool doLayer2 = weight2 > 0.05;
            
            float wTotal = (doLayer1 ? weight1 : 0.0) + (doLayer2 ? weight2 : 0.0);
            float w1_norm = (doLayer1 && wTotal > 0.0) ? (weight1 / wTotal) : 0.0;
            float w2_norm = (doLayer2 && wTotal > 0.0) ? (weight2 / wTotal) : 0.0;

            for(int k=0; k<100; k++)
            {
                float valCombined = 0.0;

                float maskDisk = GetDiskHazeMask(debugPos, iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper);
                if (maskDisk > 0.001) {
                    float r_local = length(debugPos.xz);
                    float omega = GetKeplerianAngularVelocity(r_local, 1.0, PhysicalSpinA, PhysicalQ2);
                    
                    float vDisk = 0.0;
                    if (doLayer1) {
                        float angle1 = omega * rotSpeedBase * t_offset1;
                        float c1 = cos(angle1); float s1 = sin(angle1);
                        vec3 pos1 = debugPos;
                        pos1.x = debugPos.x * c1 - debugPos.z * s1;
                        pos1.z = debugPos.x * s1 + debugPos.z * c1;
                        pos1.y += VerticalDrift1; 
                        vDisk += GetBaseNoise(pos1) * w1_norm;
                    }
                    if (doLayer2) {
                        float angle2 = omega * rotSpeedBase * t_offset2;
                        float c2 = cos(angle2); float s2 = sin(angle2);
                        vec3 pos2 = debugPos;
                        pos2.x = debugPos.x * c2 - debugPos.z * s2;
                        pos2.z = debugPos.x * s2 + debugPos.z * c2;
                        pos2.y += VerticalDrift2;
                        vDisk += GetBaseNoise(pos2) * w2_norm;
                    }
                    valCombined += maskDisk * max(0.0, vDisk - HAZE_DENSITY_THRESHOLD);
                }

                float maskJet = GetJetHazeMask(debugPos, iInterRadiusRs, iOuterRadiusRs);
                if (maskJet > 0.001) {
                    float v_jet_mag = 0.9;
                    float vJet = 0.0;
                    
                    if (doLayer1) {
                        float dist1 = v_jet_mag * jetSpeedBase * t_offset1;
                        vec3 pos1 = debugPos; pos1.y -= sign(debugPos.y) * dist1;
                        vJet += GetBaseNoise(pos1) * w1_norm;
                    }
                    if (doLayer2) {
                        float dist2 = v_jet_mag * jetSpeedBase * t_offset2;
                        vec3 pos2 = debugPos; pos2.y -= sign(debugPos.y) * dist2;
                        vJet += GetBaseNoise(pos2) * w2_norm;
                    }
                    valCombined += maskJet * max(0.0, vJet - HAZE_DENSITY_THRESHOLD);
                }
                
                debugAccum += valCombined * 0.1; 
                debugPos += rayDirNorm * debugStep;
            }
            
           Result += 0.1*vec4(vec3(min(1.0, debugAccum)), 1.0);
        }
        

        //几何剔除优化
        if (IsInHazeBoundingVolume(pos_Rg_Start, totalProbeDist, iOuterRadiusRs)) 
        {
            vec3 accumulatedForce = vec3(0.0);
            float totalWeight = 0.0;

            // 累积探测
            for (int i = 0; i < HAZE_PROBE_STEPS; i++)
            {
                float marchDist = float(i + 1) * HAZE_STEP_SIZE; 
                vec3 probePos_Rg = pos_Rg_Start + rayDirNorm * marchDist;

                float t = float(i+1) / float(HAZE_PROBE_STEPS);
                float weight = min(min(3.0*t, 1.0), 3.05 - 3.0*t);
                
                vec3 forceSample = GetHazeForce(probePos_Rg, hazeTime, PhysicalSpinA, PhysicalQ2,
                                              iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper,
                                              iAccretionRate);
                
                accumulatedForce += forceSample * weight;
                totalWeight += weight;
            }

            vec3 avgHazeForce = accumulatedForce / max(0.001, totalWeight);

            // 偏转应用
            float forceMagSq = dot(avgHazeForce, avgHazeForce);
            if (forceMagSq > 1e-10)
            {
                vec3 forcePerp = avgHazeForce - dot(avgHazeForce, rayDirNorm) * rayDirNorm;
                // 计算总偏转量
                vec3 deflection = forcePerp * HAZE_STRENGTH * 25.0; 
                RayDir = normalize(RayDir + deflection * 0.1); 
                LastDir = RayDir;
            }
            if(iDEBUG==1)
            {
                if (length(avgHazeForce) > 1e-4) {
                    vec3 debugVec = normalize(avgHazeForce) * 0.5 + 0.5;
                    debugVec *= (0.5 + 10.0 * length(avgHazeForce)); 
                    Result += 0.1*vec4(debugVec, 1.0);
                }
            }
        }

    }
    
    bool isoutgoing = false; 
    if (iObserverMode == -1 || iObserverMode == 2) {
        isoutgoing = (iCamDataCoordisOutgoing == 1);
    }
    //if(iWhitehole==1) isoutgoing=true;//test
    //if (bShouldContinueMarchRay) {
    //    // --- 测试 Ingoing 系 ---
    //    vec4 P_in = GetInitialMomentum(iObserverMode == -1 ? vec3(-ViewDirLocal.xy, ViewDirLocal.z) : RayDir, X, iObserverMode, iUniverseSign, PhysicalSpinA, PhysicalQ2, GravityFade, false);
    //    float score_in = 1e38; // 评分标准：|P^t|，越小越好
    //    if (P_in != vec4(114514.0)) {
    //        KerrGeometry geo_in;
    //        ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, iUniverseSign, false, geo_in);
    //        score_in = abs(RaiseIndex(P_in, geo_in).w); 
    //    }
    //
    //    // --- 测试 Outgoing 系 (仅在允许最大延拓时进行，常规黑洞无需测试) ---
    //    vec4 P_out = vec4(114514.0);
    //    float score_out = 1e38;
    //    if (iWhitehole == 1) {
    //        P_out = GetInitialMomentum(iObserverMode == -1 ? vec3(-ViewDirLocal.xy, ViewDirLocal.z) : RayDir, X, iObserverMode, iUniverseSign, PhysicalSpinA, PhysicalQ2, GravityFade, true);
    //        if (P_out != vec4(114514.0)) {
    //            KerrGeometry geo_out;
    //            ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, iUniverseSign, true, geo_out);
    //            score_out = abs(RaiseIndex(P_out, geo_out).w);
    //        }
    //    }
    //
    //    // --- 竞态选择最优坐标系 ---
    //    if (score_out < score_in && P_out != vec4(114514.0)) {
    //        isoutgoing = true;
    //        P_cov = P_out;
    //    } else {
    //        isoutgoing = false;
    //        P_cov = P_in;
    //    }
    //}
    
    //// 两边都崩溃了，或者不符合物理规范，直接黑屏
    //if (P_cov == vec4(114514.0)) {
    //    bShouldContinueMarchRay = false;
    //    bWaitCalBack = false;
    //    Result = vec4(0.0, 0.0, 0.0, 1.0);
    //}
    if (bShouldContinueMarchRay) {
       P_cov = GetInitialMomentum(iObserverMode == -1 ? vec3(-ViewDirLocal.xy, ViewDirLocal.z) : RayDir, X, iObserverMode, CurrentUniverseSign, PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing);
       
       // 如果被拦截（观者在该系下变成类空），且允许最大延拓，说明这是向外运动(如出白洞)的观者
       if (P_cov == vec4(114514.0) && iWhitehole == 1) {    //注意，此处有未定位的bug，导致角度变化
       //    // 1. 记录旧的坐标用于反解旋转矩阵
       //    vec4 X_old = X;
       //    vec4 dummyP = vec4(0.0); // 传入一个假动量，因为我们这步只需要变 X
       //    
       //    // 2. 将坐标变换到 Outgoing 系 (out_to_in = false)
       //    // transformKerrSchild_YSpin(X, iUniverseSign, dummyP, CONST_M, PhysicalSpinA, PhysicalQ2, false);
       //    
       //    // 3. 反解旋转矩阵的 sin 和 cos，并同步旋转 RayDir
       //    float rho2 = X_old.x * X_old.x + X_old.z * X_old.z;
       //    if (rho2 > 1e-12) {
       //        float cos_a = (X_old.x * X.x + X_old.z * X.z) / rho2;
       //        float sin_a = (X_old.z * X.x - X_old.x * X.z) / rho2;
       //        
       //        vec3 oldDir = RayDir;
       //        RayDir.x = oldDir.z * sin_a + oldDir.x * cos_a;
       //        RayDir.z = oldDir.z * cos_a - oldDir.x * sin_a;
       //    }
       //
       //    // 4. 切换坐标系标识
           isoutgoing = true; 
       //    
       //    // 5. 在正确的 Outgoing 坐标系下，使用变换后的 X 和 RayDir 重新计算合法的初始动量
           P_cov = GetInitialMomentum(iObserverMode == -1 ? vec3(-ViewDirLocal.xy, ViewDirLocal.z) : RayDir, X, iObserverMode, CurrentUniverseSign, PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing);
       }
    }
    if (P_cov == vec4(114514.0))
    {
        bShouldContinueMarchRay = false;
        bWaitCalBack = false;
        Result = vec4(0.0,0.0,0.0,1.0);
    }




    // -------------------------------------------------------------------------
    // 初始化偏振基底 (严格绑定到相机真实的屏幕轴)
    // -------------------------------------------------------------------------
// =========================================================================
    // 初始化偏振基底 (绑定相机屏幕，并执行严格的四维广相正交化与洛伦兹变换)
    // =========================================================================
    vec2 WP_CamX = vec2(0.0);
    vec2 WP_CamY = vec2(0.0);
    vec2 StokesQU = vec2(0.0);

    if (bShouldContinueMarchRay && iPolarization != 0) {
        // 1. 坐标系对齐：Walker-Penrose 常数必须在 Ingoing 系下计算
        vec4 X_wp = X;
        vec4 P_cov_wp = P_cov;
        if (isoutgoing) {
            // 如果光线被判定在白洞外流区，临时将其逆变换回 Ingoing 系
            transformKerrSchild_YSpin(X_wp, CurrentUniverseSign, P_cov_wp, CONST_M, PhysicalSpinA, PhysicalQ2, true);
        }

        KerrGeometry geo_wp;
        ComputeGeometryScalars(X_wp.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, false, geo_wp);
        vec4 P_up_wp = RaiseIndex(P_cov_wp, geo_wp);

        // 2. 提取观测者四维速度 U^mu (处理狭义相对论光行差与洛伦兹变换的基础)
        vec4 U_up;
        float g_tt = -1.0 + geo_wp.f;
        float time_comp = 1.0 / sqrt(max(1e-9, -g_tt));
        U_up = vec4(0.0, 0.0, 0.0, time_comp);
        
        if (iObserverMode == 1) {
            U_up = GetFreeFallVelocity(X_wp.xyz, geo_wp, false);
        }
        if (iObserverMode == 2 || iObserverMode == -1) {
            U_up = iU_up;
            if (iCamDataCoordisOutgoing == 1) {
                KerrGeometry camGeo;
                ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade,
                                       CurrentUniverseSign, true, camGeo);
                vec4 U_cov = LowerIndex(U_up, camGeo);
                vec4 camX = X;
                transformKerrSchild_YSpin(camX, CurrentUniverseSign, U_cov,
                                           CONST_M, PhysicalSpinA, PhysicalQ2, true);
                U_up = RaiseIndex(U_cov, geo_wp);
            }
        }
        vec4 U_down = LowerIndex(U_up, geo_wp);
        float E_obs = -dot(P_up_wp, U_down); // 光子在观者局部系测量的相对论能量

        // 3. 提取相机系下纯粹的屏幕 Right(X轴) 和 Up(Y轴) 初始三维矢量

        vec4 R_up;
        vec4 Y_up;
        
        if (iObserverMode == -1) {
            // 直接读取平移输运后的水平和垂直方向四维基底
            R_up = ie1_up; 
            Y_up = ie2_up;
            
            // 确保其在正确的坐标系下 (因为 Shader 可能已经切换到了相反的系)
            bool camIsOut = (iCamDataCoordisOutgoing == 1);
            if (camIsOut) {
                KerrGeometry geo_cam;
                ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, true, geo_cam);
                vec4 R_down = LowerIndex(R_up, geo_cam);
                vec4 Y_down = LowerIndex(Y_up, geo_cam);
                
                vec4 dummyX1 = X, dummyX2 = X;
                transformKerrSchild_YSpin(dummyX1, CurrentUniverseSign, R_down, CONST_M, PhysicalSpinA, PhysicalQ2, true);
                transformKerrSchild_YSpin(dummyX2, CurrentUniverseSign, Y_down, CONST_M, PhysicalSpinA, PhysicalQ2, true);
                
                R_up = RaiseIndex(R_down, geo_wp);
                Y_up = RaiseIndex(Y_down, geo_wp);
            }
        } else {
            vec3 rawCamRight = vec3(1.0, 0.0, 0.0);
            vec3 rawCamUp    = vec3(0.0, 1.0, 0.0);
            vec3 Right_BHLocal = WorldToLocalRot * (iInverseCamRot * vec4(rawCamRight, 0.0)).xyz;
            vec3 Up_BHLocal    = WorldToLocalRot * (iInverseCamRot * vec4(rawCamUp, 0.0)).xyz;
            R_up = vec4(Right_BHLocal, 0.0);
            Y_up = vec4(Up_BHLocal, 0.0);
            
            // 下方将这组基底正交化。
        }

        // 将相机基底投影到观者的局部空间
        if (iObserverMode != -1) { 
            // 如果是模式 -1，则 ie1_up 和 ie2_up 在传入时已经被严格 GramSchmidt 正交化过，不需要再次执行
            R_up += dot(R_up, U_down) * U_up;
            Y_up += dot(Y_up, U_down) * U_up;
        }
        vec4 R_down = LowerIndex(R_up, geo_wp);
        vec4 Y_down = LowerIndex(Y_up, geo_wp);
        // 下一步剔除沿光子传播方向的分量。

        // 步骤 4.2: 消除径向分量，确保基底垂直于光子运动方向 (F · P = 0)
        // 构造光子在观者局部系下的纯空间方向 D^mu = P^mu - E * U^mu
        vec4 D_up = P_up_wp - E_obs * U_up;
        vec4 D_down = LowerIndex(D_up, geo_wp);
        float invE2 = 1.0 / max(1e-12, E_obs * E_obs); // D^mu 的模长平方恒等于 E^2

        // 在 4D 度规下剔除 D^mu 方向的投影分量
        vec4 FX_up = R_up - (dot(R_up, D_down) * invE2) * D_up;
        vec4 FY_up = Y_up - (dot(Y_up, D_down) * invE2) * D_up;

        vec4 FX_down = LowerIndex(FX_up, geo_wp);
        vec4 FY_down = LowerIndex(FY_up, geo_wp);

        // 步骤 4.3: 在弯曲时空度规下归一化 (使得 F · F = 1)
        float normX = sqrt(max(1e-12, dot(FX_up, FX_down)));
        float normY = sqrt(max(1e-12, dot(FY_up, FY_down)));
        FX_down /= normX;
        FY_down /= normY;

        // 5. 此时的 FX, FY 已经是包含广相弯曲+狭相光行差修正后的完美四维横向偏振矢量
        float r_start = KerrSchildRadius(X_wp.xyz, PhysicalSpinA, CurrentUniverseSign);
        WP_CamX = GetWalkerPenrose(X_wp, P_cov_wp, FX_down, PhysicalSpinA,PhysicalQ2, r_start);
        WP_CamY = GetWalkerPenrose(X_wp, P_cov_wp, FY_down, PhysicalSpinA,PhysicalQ2, r_start);
    }



    //    if (P_cov == vec4(114514.0))
    //{
    //    bShouldContinueMarchRay = false;
    //    bWaitCalBack = false;
    //    Result = vec4(0.0,0.0,0.0,1.0);
    //}

    // ==== 调试接管分支 ====
    if (iDEBUG == 2 && bShouldContinueMarchRay)
    {
        vec3 dbgColor = DebugInitialMomentum(
            P_cov, X, iObserverMode, CurrentUniverseSign, 
            PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing, iCameraVelocity.xyz
        );
        res.AccumColor = vec4(dbgColor, 1.0);
        res.Status = 3.0; // 设置为不透明直接返回，绘制到屏幕
        return res;
    }
    // ========================

    E_conserved = -P_cov.w;
    //if(iGrid==0 && E_conserved<0.0){ res.FreqShift=0.0;res.AccumColor=vec4(0.0);  res.Status = 0.0; return res;}//剔除最大延拓解下II/IV区内从 平行宇宙 去往/来自 平行虫洞 的光。（视界内和观者相向而行）    开启网格时会误伤能层内部分从网格发出的光线，igrid非0时的剔除改为视界间进行
    // -------------------------------------------------------------------------
    // 初始合法性检查与终结半径
    // -------------------------------------------------------------------------
    float TerminationR = -1.0; 
    bool HasTerminationR = false;
    float CameraStartR = KerrSchildRadius(RayPosLocal, PhysicalSpinA, CurrentUniverseSign);
    
    if (bShouldContinueMarchRay)
    {
        // 静态观者能层合法性检查
        if (iObserverMode == 0) 
        {
            float CosThetaSq = (RayPosLocal.y * RayPosLocal.y) / (CameraStartR * CameraStartR + 1e-20);
            float SL_Discrim = 0.25 - PhysicalQ2 - PhysicalSpinA * PhysicalSpinA * CosThetaSq;
            
            if (SL_Discrim >= 0.0) {
                float SL_Outer = 0.5 + sqrt(SL_Discrim);
                float SL_Inner = 0.5 - sqrt(SL_Discrim); 
                
                if (CameraStartR < SL_Outer && CameraStartR > SL_Inner) {
                    bShouldContinueMarchRay = false; 
                    bWaitCalBack = false; 
                    Result = vec4(0.0, 0.0, 0.0, 1.0); 
                } 
            }
        }
        else
        {
        // 落体观者能层合法性检查 todo
        }
        // 确定光线追踪终止半径 (非裸奇点)
        if (!bIsNakedSingularity && iWhitehole==0)
        {
            if (CameraStartR > EventHorizonR) TerminationR = EventHorizonR; 
            else if (CameraStartR > InnerHorizonR) TerminationR = InnerHorizonR;
            HasTerminationR = CameraStartR > InnerHorizonR;
        }
    }
    
    //计算光子壳最窄处作为回落剔除判断
    float ProgradePhotonRadius = bIsNakedSingularity ? 0.0 :
        EquatorialPhotonRadius(CONST_M, PhysicalQ2, abs(PhysicalSpinA), false);


    float Extremality = 4.0 * HorizonDiscrim;
    float MaxStep=150.0+300.0/(1.0+1000.0*Extremality*Extremality);
    if(iWhitehole==1) MaxStep=1145.0;
    if(bIsNakedSingularity) MaxStep=450.0;//150.0+300.0/(1.0+10.0*(1.0-iSpin*iSpin-iQ*iQ)*(1.0-iSpin*iSpin-iQ*iQ));
    else if (CameraStartR < InnerHorizonR) MaxStep = max(MaxStep, 450.0); // 内部观者的光可绕过奇环后再逃逸。

    // -------------------------------------------------------------------------
    // 主循环
    // -------------------------------------------------------------------------
    int Count = 0;
    float lastR = 0.0;
    bool bIntoOutHorizon = false;
    bool bIntoInHorizon = false;
    bool bEscapeOutHorizon = false;
    bool bEscapeInHorizon = false;
    int universeoffset=0;
    if(iWhitehole == 1 && !bIsNakedSingularity && CameraStartR <InnerHorizonR) universeoffset++;
    float LastDr = 0.0;           
    int RadialTurningCounts = 0;  
    float RayMarchPhase = RandomStep(FragUv, iTraceTime); 
    float ThetaInShell=0.0;
    bool shiftinout=false;
    bool fromwhitehole=false;
    vec4 LastX_ingoing;
    vec4 X_ingoing = X;
    vec4 P_cov_ingoing = P_cov;
    vec4 LastP_cov_ingoing = P_cov_ingoing; // 用于保存上一步的局域四动量
    if(P_cov== vec4(0.0,0.0,0.0,-1.0))	{
        P_cov_ingoing.xyz = -RayDir;
    }
    else{
        if (isoutgoing) {
            transformKerrSchild_YSpin(X_ingoing, CurrentUniverseSign, P_cov_ingoing, CONST_M, PhysicalSpinA, PhysicalQ2, isoutgoing);
        }
        LastX_ingoing = X_ingoing;
        LastP_cov_ingoing = P_cov_ingoing; // 初始化 LastP_cov
    }
    // ----------------------------------------
    KerrGeometry geo;
    ComputeGeometryScalars(X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, isoutgoing, geo);
    State InitialState; InitialState.X = X; InitialState.P = P_cov;
    State k1 = GetDerivativesAnalytic(InitialState, PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing, geo);
#if iAdaptiveStepFeedback == 1
    float NextStep = -1.0;
    float IntegrationTolerance = max(iFeedbackTolerance / pow(max(iQuality, 0.25), 4.0), 2e-8);
    float FeedbackRadius = max(100.0, 8.0 * CONST_M + 2.0 * abs(PhysicalSpinA) + 2.0 * sqrt(abs(PhysicalQ2)));
    float FeedbackRadiusSq = FeedbackRadius * FeedbackRadius;
    float InitialStaticLimitWeight = 0.0;
#endif
#if ANTIVERSE_RAIN_3D == 1
    vec4 flatRainStart=vec4(0.0), flatRainEnd=vec4(0.0);
    float flatRainPath=0.0;
    bool flatRainPending=false;
    // 平直区也从实际相机位置发射光线，先合成前景，再接入引力范围。
    if (RainSheet(CurrentUniverseSign) && DistanceToBlackHole>RaymarchingBoundary && bShouldContinueMarchRay) {
        vec3 direction = normalize(-k1.X.xyz);
        float b = dot(X.xyz,direction);
        float discriminant = b*b-dot(X.xyz,X.xyz)+pow(RaymarchingBoundary-1.0,2.0);
        if (discriminant>=0.0 && -b-sqrt(discriminant)>0.0) {
            float distanceToEntry = -b-sqrt(discriminant);
            vec4 origin = X_ingoing;
            X += vec4(direction,-k1.X.w/max(length(k1.X.xyz),1e-20))*distanceToEntry;
            X_ingoing=X; P_cov_ingoing=P_cov;
            if (isoutgoing) transformKerrSchild_YSpin(X_ingoing,CurrentUniverseSign,P_cov_ingoing,CONST_M,PhysicalSpinA,PhysicalQ2,isoutgoing);
            flatRainStart=origin; flatRainEnd=X_ingoing;
            flatRainPending=true;
            rainPathLength=distanceToEntry;
            DistanceToBlackHole=length(X.xyz);
            GravityFade=CubicInterpolate(clamp(1.0-(DistanceToBlackHole-100.0)/(RaymarchingBoundary-100.0),0.0,1.0));
            ComputeGeometryScalars(X.xyz,PhysicalSpinA,PhysicalQ2,GravityFade,CurrentUniverseSign,isoutgoing,geo);
            InitialState.X=X; InitialState.P=P_cov;
            k1=GetDerivativesAnalytic(InitialState,PhysicalSpinA,PhysicalQ2,GravityFade,isoutgoing,geo);
        }
    }
#endif
    float dLambda=0.0, ActualStepLength_ingoing=0.0, rainStartSign=CurrentUniverseSign;
    vec4 LastX=vec4(0.0), LastP_cov=vec4(0.0);
    KerrGeometry finalGeo;
#if ANTIVERSE_RAIN_3D == 1
    // 所有光段按先后顺序通过同一数字雨求交入口。
    while (true) {
        bool didStep=false;
        if (!flatRainPending && bShouldContinueMarchRay) {
            do {
#else
    while (bShouldContinueMarchRay) {
#endif
        DistanceToBlackHole = length(X.xyz);
        if (DistanceToBlackHole > RaymarchingBoundary)
        { 
            bShouldContinueMarchRay = false; 
            bWaitCalBack = true; 
            break;  //离开足够远
        }
        
        if (HasTerminationR && geo.r < TerminationR && !bIsNakedSingularity && iWhitehole==0)
        { 
            bShouldContinueMarchRay = false;
            bWaitCalBack = false;
            if(iDEBUG==1) Result += vec4(0.0, 0.3, 0.3, 0.0); 
            break;  //视界判定情况1，直接进入视界判定区
        }

        if (Count >int(float( MaxStep)*iQuality*(1.0+0.3*iQuality))) 
        { 
            bShouldContinueMarchRay = false; 
            bWaitCalBack = false;
            if(bIsNakedSingularity&&RadialTurningCounts <= 2) bWaitCalBack = true;
            if(iDEBUG==1) Result += vec4(0.0, 0.3, 0.0, 0.0);
            break; //耗尽步数
        }

        // 只限制预计算的重复积分；未完成的光线由完整分辨率阶段重新追踪。
        if (PrepassSteps > 0 && Count >= PrepassSteps) {
            res.Status = -1.0;
#if ANTIVERSE_RAIN_3D == 1
            break;
#else
            return res;
#endif
        }
        State s0; s0.X = X; s0.P = P_cov;

        float CurrentDr = dot(geo.grad_r, k1.X.xyz);
#if iEnableShadowCulling == 1 && iGrid == 0 && iWhitehole == 0
        // 完整度规内只判定一次；不因后续积分漂移将逃逸侧扩成阴影。
        if (shadowState==0 && !bIsNakedSingularity && CurrentUniverseSign>0.0
            && iDensestarsurfaceR==0.0 && geo.r>EventHorizonR && EventHorizonR>0.0
            && GravityFade==1.0 && geo.r*geo.r+PhysicalSpinA*PhysicalSpinA<10000.0
            && abs(dot(P_cov,k1.X))<1e-5*max(P_cov.w*P_cov.w,1e-12))
        {
            shadowState = ShadowCaptured(X.xyz, P_cov, geo.r, CurrentDr,
                PhysicalSpinA, PhysicalQ2, EventHorizonR) ? 2 : 1;
        }
        if (shadowState==2 && !(RainVolumeSheet(CurrentUniverseSign) && rainPathLength<RAIN_DISTANCE_RS))
        {
            bool noMatter = !hasShadowDisk && !hasShadowJet && iUseImageDisk==0;
            float matterInner = ShadowMatterInnerRadius(PhysicalSpinA, hasShadowDisk, hasShadowJet);
            float safeR = EventHorizonR+clamp(SHADOW_CULLING_PUSH_RATIO,0.0,1.0)
                         * max(0.0,matterInner-EventHorizonR);
            // 先向外的捕获光线仍可能遇到盘，只有向内且已进入真空间隙才提前终止。
            if (noMatter || (CurrentDr>0.0 && geo.r<safeR))
            {
                bShadowTerminated = true;
                bShouldContinueMarchRay = false;
                bWaitCalBack = false;
                break;
            }
        }
#endif
        shiftinout = false;

        if (Count > 0 && CurrentDr * LastDr < 0.0) RadialTurningCounts++;
        if (Count==0) lastR = geo.r;

        if (geo.r < max(1.0, EventHorizonR + 0.5) || isoutgoing || iWhitehole == 1)
        {
            vec4 P_contra = RaiseIndex(P_cov, geo);
            float current_Sum = dot(abs(P_contra), vec4(1.0));
            // 试探换系
            vec4 test_X = X;
            vec4 test_P = P_cov;
            transformKerrSchild_YSpin(test_X, CurrentUniverseSign, test_P, CONST_M, PhysicalSpinA, PhysicalQ2, isoutgoing);
            
            KerrGeometry test_geo;
            ComputeGeometryScalars(test_X.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, !isoutgoing, test_geo);
            
            vec4 test_P_contra = RaiseIndex(test_P, test_geo);
            float test_Sum = dot(abs(test_P_contra), vec4(1.0));
            
            if (current_Sum > 2.0 * test_Sum) 
            {
                X = test_X;
                P_cov = test_P;
                isoutgoing = !isoutgoing;
                geo = test_geo;
                s0.X = X; 
                s0.P = P_cov;
                k1 = GetDerivativesAnalytic(s0, PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing, geo);
                CurrentDr = dot(geo.grad_r, k1.X.xyz);
                shiftinout = true;
#if iAdaptiveStepFeedback == 1
                NextStep = -1.0;
#endif
            
            
                //Result+=vec4(0.0,0.2,0.0,0.5)*(1.0-Result.a);
            }
        }
        LastDr = CurrentDr;

        if(geo.r < InnerHorizonR && lastR > InnerHorizonR) bEscapeInHorizon = true;    //检测穿进(追踪方向)内视界   
        if(geo.r < EventHorizonR && lastR > EventHorizonR) bEscapeOutHorizon = true;   //检测穿进(追踪方向)外视界   

        if(iWhitehole == 1 && !bIsNakedSingularity && geo.r < InnerHorizonR && lastR > InnerHorizonR) universeoffset++;    

        if (RadialTurningCounts > 2 )//靠近最大延拓黑洞时，能从月牙形阴影看到上上及更上宇宙的内容，但是这里暂时拦下
        {
            bShouldContinueMarchRay = false; bWaitCalBack = false;
            if(iDEBUG==1) Result += vec4(0.3, 0.0, 0.3, 1.0); 
            break;//识别剔除束缚态光子轨道
        }

        

        if(iGrid==0 && iWhitehole==0 && !(RainVolumeSheet(CurrentUniverseSign) && rainPathLength<RAIN_DISTANCE_RS))
        {
            if(geo.r > InnerHorizonR && lastR < InnerHorizonR) bIntoInHorizon = true;   //检测穿出(追踪方向)内视界    
            if(geo.r > EventHorizonR && lastR < EventHorizonR) bIntoOutHorizon = true;  //检测穿出(追踪方向)外视界    

            if ((CurrentUniverseSign > 0.0 || InnerHorizonR < 0.0) && !bIsNakedSingularity && iWhitehole==0)
            {
                float SafetyGap = 0.001;
                float ToHorizonGap = 0.2;
                float PhotonShellLimit = ProgradePhotonRadius - SafetyGap; 
                float preCeiling = min(CameraStartR - SafetyGap, TerminationR + ToHorizonGap);
                if(bIntoInHorizon)  { preCeiling = InnerHorizonR + ToHorizonGap; } //处理 射线从相机出发 -> 向外运动 -> 调头 -> 向内运动 -> 撞击内视界 的光
                if(bIntoOutHorizon) { preCeiling = EventHorizonR + ToHorizonGap; } //处理 射线从相机出发 -> 向外运动 -> 调头 -> 向内运动 -> 撞击外视界 的光
                
                float PruningCeiling = min(iInterRadiusRs, preCeiling);
                PruningCeiling = min(PruningCeiling, PhotonShellLimit); 
                if(iDensestarsurfaceR!=0.0) PruningCeiling = min(PruningCeiling, iDensestarsurfaceR); 
                
            
                if (geo.r < PruningCeiling)
                {
                    float DrDlambda = dot(geo.grad_r, k1.X.xyz);
                    if (DrDlambda > 1e-4) 
                    {
                        bShouldContinueMarchRay = false;
                        bWaitCalBack = false;
                        if(iDEBUG==1) Result += vec4(0.0, 0., 0.3, 0.0);
                        break;  //视界判定情况2，对凝结在视界前的光提前剔除
                    }
                }
            }
        }

        // 几何与力给出试探步上限，局部误差处理正负电荷及小内视界。
        float rho = length(X.xz);
        float DistRing = sqrt(X.y * X.y + pow(rho - abs(PhysicalSpinA), 2.0));
        float Vel_Mag = length(k1.X); 
        float Force_Mag = length(k1.P);
        float Mom_Mag = length(P_cov);
        
        float StepGeo =  DistRing / (Vel_Mag + 1e-9);
        float StepForce = Mom_Mag / (Force_Mag + 1e-15);
        
        dLambda = 0.5 * min(StepGeo, StepForce);
#if iAdaptiveStepFeedback == 1
        dLambda *= iFeedbackStepScale;
        // 首步和换系后没有可信的误差历史，用短试探步建立反馈。
        if (Count == 0 || shiftinout) dLambda = min(dLambda, 0.1 * min(StepGeo, StepForce));
        // 内视界内的静止极限和负电荷曲率需要独立上限，不能只等上一小步反馈。
        if (!bIsNakedSingularity && geo.r < InnerHorizonR) {
            float nearStaticLimit = clamp(1.0 - abs(1.0 - geo.f), 0.0, 1.0);
            if (Count == 0) InitialStaticLimitWeight = nearStaticLimit;
            dLambda *= mix(1.0, clamp(abs(iSpin), 0.25, 1.0), max(nearStaticLimit, InitialStaticLimitWeight));
        }
        if (PhysicalQ2 < 0.0) {
            float sigma = geo.r2 + PhysicalSpinA * PhysicalSpinA * X.y * X.y / max(geo.r2, 1e-20);
            float chargeStep = 0.15 * sigma / max(sqrt(-PhysicalQ2) * Mom_Mag, 1e-15);
            dLambda = min(dLambda, chargeStep);
        }
        if (DistanceToBlackHole > 100.0)
            dLambda = min(dLambda, (RaymarchingBoundary - 100.0) * 0.2 * iQuality / max(length(k1.X.xyz), 1e-15));
        if (NextStep > 0.0) dLambda = min(dLambda, NextStep * iQuality);
#endif
        dLambda = max(dLambda, 1e-7); 

        LastX = X;
        LastP_cov=P_cov;
        LastX_ingoing = X_ingoing;
        LastP_cov_ingoing = P_cov_ingoing; // 缓存步进前的协变四动量
        // --------------------------------------------------

#if iAdaptiveStepFeedback == 0
        GravityFade = CubicInterpolate(max(min(1.0 - ( DistanceToBlackHole - 100.0) / (RaymarchingBoundary - 100.0), 1.0), 0.0));
#endif
        
        vec4 P_contra_step = RaiseIndex(P_cov, geo);
        float Pdangerous=10000.0*max(1.0,pow(0.5/max(abs(iSpin),1e-6),3.0));
        if (P_contra_step.w > Pdangerous*iQuality && !bIsNakedSingularity && (CurrentUniverseSign > 0.0 || InnerHorizonR < 0.0))
        { 
            bShouldContinueMarchRay = false; 
            bWaitCalBack = false;
            if(iDEBUG==1) Result += vec4(0.3, 0.3, 0.2, 0.0);  
            break; //视界判定情况3，凝结在视界
        }


        #if iAdaptiveStepFeedback == 1
        StepGeodesicAdaptive(X, P_cov, E_conserved, -dLambda / iQuality, NextStep, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, isoutgoing, DistRing, IntegrationTolerance, FeedbackRadiusSq, RaymarchingBoundary, k1, finalGeo);
#else
        StepGeodesicRK4_Optimized(X, P_cov, E_conserved, -dLambda / iQuality, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, isoutgoing, finalGeo, k1);
        State nextState; nextState.X = X; nextState.P = P_cov;
        k1 = GetDerivativesAnalytic(nextState, PhysicalSpinA, PhysicalQ2, GravityFade, isoutgoing, finalGeo);
#endif
        float deltar = geo.r - lastR;


        // 大概在这里分界，上面的内容基本上对 inout 不敏感，比如半径。

        // 将步进结果转换为统一的 Ingoing 系供后续渲染

        //获取当前步在 Ingoing 系下的状态
        X_ingoing = X;
        P_cov_ingoing = P_cov;
        if (isoutgoing) {
            transformKerrSchild_YSpin(X_ingoing, CurrentUniverseSign, P_cov_ingoing, CONST_M, PhysicalSpinA, PhysicalQ2, isoutgoing);
        }

        
        vec3 StepVec_ingoing = X_ingoing.xyz - LastX_ingoing.xyz; // 直接用 LastX_ingoing
        ActualStepLength_ingoing = length(StepVec_ingoing);


        float drdl = deltar / max(ActualStepLength_ingoing, 1e-9);

        float rotfact = clamp(1.0 + iBoostRot * dot(-StepVec_ingoing, vec3(X_ingoing.z, 0.0, -X_ingoing.x)) / ActualStepLength_ingoing / length(X_ingoing.xz) * clamp(iSpin, -1.0, 1.0), 0.0, 2.0);
        if(CurrentUniverseSign > 0.0 && geo.r > InnerHorizonR && geo.r < 1.6 + pow(abs(iSpin), 0.666666)){
            ThetaInShell += ActualStepLength_ingoing / (0.5*lastR + 0.5*geo.r) / (1.0 + 1000.0*drdl*drdl) * rotfact * clamp(11.0 - 10.0*(iSpin*iSpin + iQ2), 0.0, 1.0);
        }

        lastR = geo.r;
        
        rainStartSign=CurrentUniverseSign;
        if (LastX.y * X.y < 0.0) { 
            float t_cross = LastX.y / (LastX.y - X.y);
            float rho_cross = length(mix(LastX.xz, X.xz, t_cross));
            if (rho_cross < abs(PhysicalSpinA)) CurrentUniverseSign *= -1.0;
        }
#if ANTIVERSE_RAIN_3D == 1
                didStep=true;
            } while (false);
        }
        // 在单步作用域外返回未完成标记，交由完整分辨率阶段重算。
        if (res.Status<0.0) return res;
        bool rainTail=false;
        if (!didStep && !flatRainPending) {
            if (iDEBUG==3 || !(bWaitCalBack && RainSheet(CurrentUniverseSign) && rainPathLength<RAIN_DISTANCE_RS)) break;
            KerrGeometry exitGeometry;
            ComputeGeometryScalars(X_ingoing.xyz,PhysicalSpinA,PhysicalQ2,GravityFade,CurrentUniverseSign,false,exitGeometry);
            vec4 tangent=RaiseIndex(P_cov_ingoing,exitGeometry);
            float spatialSpeed=max(length(tangent.xyz),1e-20);
            flatRainStart=X_ingoing;
            flatRainEnd=X_ingoing-tangent/spatialSpeed*(RAIN_DISTANCE_RS-rainPathLength);
            flatRainPath=rainPathLength;
            rainTail=true;
        }
        vec4 rainFrom=flatRainStart, rainTo=flatRainEnd;
        float rainPath=flatRainPath, rainSign=CurrentUniverseSign;
        if (didStep) {
            float begin=0.0, end=1.0;
            rainSign=rainStartSign;
            if (rainStartSign!=CurrentUniverseSign) {
                float crossing=clamp(LastX_ingoing.y/(LastX_ingoing.y-X_ingoing.y),0.0,1.0);
                // 奇环两侧只有一侧发出数字雨的光。
                if (RainSheet(rainStartSign)) end=crossing;
                else {begin=crossing;rainSign=CurrentUniverseSign;}
            }
            rainFrom=mix(LastX_ingoing,X_ingoing,begin);
            rainTo=mix(LastX_ingoing,X_ingoing,end);
            rainPath=rainPathLength+ActualStepLength_ingoing*begin;
        }
        TraceRainSegment(Result,rainFrom,rainTo,rainPath,E_conserved,rainSign,universeoffset,
                         PhysicalSpinA,PhysicalQ2,RaymarchingBoundary);
        if (!didStep) {
            flatRainPending=false;
            if (rainTail) break;
            continue;
        }
        rainPathLength+=ActualStepLength_ingoing;
#endif
        geo = finalGeo;
        bool ShowInnerGrid=true;
        if (iWhitehole == 0 && !bIsNakedSingularity && //类似于视界判定情况1，直接进入视界判定区，这个在有网格也生效.这个判定和上面的直接进入判定以及更下面的不可逃逸剔除有重叠，但这个必须在最前面（），为了InnerGrid不漏光，因为ks系步长可以一次从外视界外进到内视界内，导致在外面看到内视界
            ( 
                (lastR > EventHorizonR && geo.r < EventHorizonR) ||                                                                   // 1. 上一步外视界外，这一步外视界内
                (lastR > InnerHorizonR && geo.r < InnerHorizonR) ||                                                                   // 2. 上一步内视界外，这一步内视界内
                (lastR > EventHorizonR && geo.r < InnerHorizonR) ||                                                                   // 3. 上一步外视界外，这一步内视界内
                (lastR < EventHorizonR && lastR > InnerHorizonR && geo.r < EventHorizonR && geo.r > InnerHorizonR && geo.r < lastR)   // 4. 两步都在视界间但是向内了
            )
        ){ 
            bShouldContinueMarchRay = false; 
            bWaitCalBack = false; 
            ShowInnerGrid=false;
        }
        if (CurrentUniverseSign > 0.0 && iBlackHoleMassSol > 0.0 &&   int(33+iInWhichUniverse-universeoffset)%3==0       )
        {
           if(IsAccretionDiskVisible(iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper, iBrightmut, iDarkmut))
           {
               float activeThetaInShell = (bEscapeInHorizon || geo.r <= InnerHorizonR) ? 0.0 : ThetaInShell;
               Result = DiskColor(Result, X, LastX,  P_cov,LastP_cov, E_conserved,
                             iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper, iBrightmut, iDarkmut, iReddening, iSaturation, DiskArgument, 
                             iBlackbodyIntensityExponent, iRedShiftColorExponent, iRedShiftIntensityExponent, PeakTemperature, ShiftMax, 
                             abs(lastR), abs(geo.r), PhysicalSpinA,
                             PhysicalQ2, isoutgoing,
                             activeThetaInShell,
                             RayMarchPhase,WP_CamX, WP_CamY, StokesQU 
                             ); 


           }
           if(IsJetVisible(iAccretionRate, iJetBrightmut)){
               Result = JetColor(Result, X, LastX, P_cov, LastP_cov, E_conserved,
                             iInterRadiusRs, iOuterRadiusRs, iJetRedShiftIntensityExponent, iJetBrightmut, iReddening, iJetSaturation, iAccretionRate, iJetShiftMax, 
                             PhysicalSpinA, 
                             PhysicalQ2, isoutgoing,               // 传入当前的 isoutgoing 标志
                             RayMarchPhase 
                             ); 
           }
                          if(iUseImageDisk!=0){Result = ImageDiskColor(diskTexture, Result, X, LastX, P_cov, LastP_cov,
                                       PhysicalSpinA, PhysicalQ2, isoutgoing,
                                       CurrentUniverseSign, -dLambda/iQuality,
                                       iInterRadiusRs, iOuterRadiusRs,
                                       iRedShiftColorExponent, iRedShiftIntensityExponent);
                                       }
        }
        // if (CurrentUniverseSign > 0.0 && iBlackHoleMassSol > 0.0 &&   int(33+iInWhichUniverse-universeoffset)%3==1       )
        //{
        //   if(IsAccretionDiskVisible(iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper, iBrightmut, iDarkmut))
        //   {
        //       Result = DiskColortoBlue(Result, ActualStepLength_ingoing, X_ingoing, LastX_ingoing, RayDir_ingoing, LastDir_ingoing, P_cov_ingoing, E_conserved,
        //                     iInterRadiusRs, iOuterRadiusRs, iThinRs, iHopper, iBrightmut, iDarkmut, iReddening, iSaturation, DiskArgument, 
        //                     iBlackbodyIntensityExponent, iRedShiftColorExponent, iRedShiftIntensityExponent, PeakTemperature, ShiftMax, 
        //                     clamp(PhysicalSpinA, -0.49, 0.49), 
        //                     PhysicalQ2, false, 
        //                     ThetaInShell,
        //                     RayMarchPhase 
        //                     ); 
        //   }
        //   if(IsJetVisible(iAccretionRate, iJetBrightmut)){
        //       Result = JetColor(Result, ActualStepLength_ingoing, X_ingoing, LastX_ingoing, RayDir_ingoing, LastDir_ingoing, P_cov_ingoing, E_conserved,
        //                     iInterRadiusRs, iOuterRadiusRs, iJetRedShiftIntensityExponent, iJetBrightmut, iReddening, iJetSaturation, iAccretionRate, iJetShiftMax, 
        //                     clamp(PhysicalSpinA, -0.049, 0.049), 
        //                     PhysicalQ2 , false,
        //                     RayMarchPhase // <----- 补上被漏掉的这一项
        //                     ); 
        //   }
        //}
        if(iDensestarsurfaceR!=0.0&&(bIsNakedSingularity||iDensestarsurfaceR>EventHorizonR)&&   int(33+iInWhichUniverse-universeoffset)%3==0       )
        {
            Result = DensestarColor(Result, X, LastX, P_cov,LastP_cov,
                        PhysicalSpinA, 
                        PhysicalQ2, isoutgoing,
                        CurrentUniverseSign,-dLambda/iQuality);
        }
        if(iGrid==1)
        {
            // 传入真实的当前步坐标 X, LastX 以及当前的 isoutgoing 状态
            Result = GridColor(Result, X, LastX, 
                        P_cov, E_conserved,
                        PhysicalSpinA, 
                        PhysicalQ2, isoutgoing,
                        CurrentUniverseSign);
        }
        else if(iGrid==2)
        {
            Result = GridColorSimple(Result, X, LastX, P_cov,LastP_cov,
                        PhysicalSpinA, 
                        PhysicalQ2, isoutgoing,
                        CurrentUniverseSign,-dLambda/iQuality,ShowInnerGrid);
        }
        //Result = DrawFallingWhiteDot(Result, X, LastX, P_cov,LastP_cov,
        //                PhysicalSpinA, 
        //                PhysicalQ2, isoutgoing,
        //                CurrentUniverseSign,-dLambda/iQuality);
        //        if (CurrentUniverseSign > 0.0) {
        //    Result = DrawFallingTestParticle(Result, X, LastX, P_cov, LastP_cov,
        //                                     PhysicalSpinA, PhysicalQ2, isoutgoing,
        //                                     CurrentUniverseSign, -dLambda/iQuality);
        //}
        if (Result.a > 0.99) { bShouldContinueMarchRay = false; bWaitCalBack = false; break; }
        

        Count++;
    }

    if (iDEBUG == 3)
    {
        // 将步数归一化（0.0 到 1.0），MaxStep 是循环的最大限制
        float stepHeat = float(Count) / MaxStep;
        
        // 也可以使用简单的热力图颜色：蓝色(少) -> 红色(多)
        res.AccumColor = vec4(mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), stepHeat), 1.0);
        
        // 或者简单的灰度显示：
        // res.AccumColor = vec4(vec3(stepHeat), 1.0);
        
        res.Status = 3.0; // 强制标记为不透明，直接输出颜色
        return res;
    }
#if SHADOW_CULL_DEBUG == 1
    shadowCullDebugColor = bShadowTerminated ? vec3(0.0, 1.0, 0.0) : vec3(0.0);
#elif SHADOW_CULL_DEBUG == 2
    shadowCullDebugColor = bShadowTerminated ? vec3(0.0, 1.0, 0.0)
                        : shadowState==2 ? vec3(1.0, 0.8, 0.0)
                        : bWaitCalBack ? vec3(0.08) : vec3(1.0, 0.0, 0.0);
#endif
    // 结果打包
    res.CurrentSign = CurrentUniverseSign;
    res.AccumColor  = Result;
#if iPolarization != 0
    // 数字雨不参与吸积盘的偏振显示。
    res.AccumColor.rgb = max(res.AccumColor.rgb-rainRadiance,vec3(0.0));
#endif
    


    float EVPA = 0.5 * atan(StokesQU.y, StokesQU.x); 
    float PolIntensity = length(StokesQU);

    if (iPolarization==1) {
        float hue = (EVPA + kPi/2.0) / kPi;
        // 色相映射显示偏振参数
        vec3 polColor = clamp(abs(fract(hue + vec3(3.0, 2.0, 1.0)/3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        res.AccumColor = vec4(polColor * PolIntensity, Result.a);

    } 
    else if (iPolarization==2) {
        // 马吕斯定律 (滤光片): I_out = 0.5 * (I_in + Q*cos(2θ) + U*sin(2θ))
        // 实际上这等价于计算光的主偏振方向和滤光片的偏振夹角 Δθ, 其透过率为 cos^2(Δθ)
        // 1. 获取像素内极化部分的光对应的占比（如果所有光都是完全偏振的，这里的除法则抵消）
        float Q = StokesQU.x;
        float U = StokesQU.y;
        
        float maxPolIntensity = max(PolIntensity, 1e-12);
        
        // 对于完全偏振光，滤光片将其强度在 [0, 1] 间变动
        float filterTransmission = 0.5 + 0.5 * (Q * cos(2.0 * iPolarizationAngle) + U * sin(2.0 * iPolarizationAngle)) / maxPolIntensity;
        
        // 将偏振片的透射率乘到吸积盘颜色上
        // 当光经过完美的偏振片时，如果相位正对则为亮度最高点，正交则变暗甚至接近黑。
        // 你可以通过降低 0.5 增加对暗部的限制或者乘某增亮系数平衡总体视觉亮度
        res.AccumColor.rgb *= filterTransmission;
    }





#if iPolarization != 0
    res.AccumColor.rgb += rainRadiance;
#endif
    if (bShadowTerminated && iDEBUG==1) {
        res.AccumColor.rgb += vec3(0.0, 0.5, 0.0)*max(0.0,1.0-res.AccumColor.a);
        res.AccumColor.a = 1.0;
        res.Status = 3.0;
        return res;
    }
    // 状态位定义:
    // 0.0 = Absorbed/Lost (视界/超时，且未被体积光完全遮挡)
    // 1.0 = Sky (Universe +1)
    // 2.0 = Antiverse (Universe -1)
    // 3.0 = Opaque (Result.a > 0.99，体积光完全遮挡，其边界与前三者交界不做检查)
    // 4.0 = last universe
    // 5.0 = last anti-universe

    //小数位.0 .2区分能量正负，用于上色平行宇宙
    if (Result.a > 0.99) {
        res.Status = 3.0; 
        res.EscapeDir = vec3(0.0); 
        res.FreqShift = 0.0;
    } 
    else if (bWaitCalBack) {
        KerrGeometry geo_sky;
        ComputeGeometryScalars(X_ingoing.xyz, PhysicalSpinA, PhysicalQ2, GravityFade, CurrentUniverseSign, false, geo_sky); // 假定已经足够远，GravityFade取1即可，f会自然趋于0
        vec4 P_up_sky = RaiseIndex(P_cov_ingoing, geo_sky);
        
        // 天空盒方向使用Ingoing系局部动量方向
        res.EscapeDir = LocalToWorldRot * normalize(-P_up_sky.xyz);
        
        // 检测是否为 NaN 或 Inf
        bool isInvalid = any(isnan(res.EscapeDir)) || any(isinf(res.EscapeDir));
        
        if (DistanceToBlackHole > RaymarchingBoundary ) 
        {
            res.EscapeDir = LocalToWorldRot * normalize(-P_cov_ingoing.xyz);
        }
        if(isInvalid) 
        {
            res.EscapeDir = LocalToWorldRot * normalize(RayDir);
        }
        res.FreqShift = clamp(1.0 / max(1e-14, abs(E_conserved)), 1.0/iBackShiftMax, iBackShiftMax);
        if (iDEBUG == 4)
        {

            res.AccumColor = vec4(mix(vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), 0.5*(log(iBackShiftMax)+log(res.FreqShift))/(log(iBackShiftMax))), 1.0);

        
            res.Status = 3.0; // 强制标记为不透明，直接输出颜色
            return res;
        }
        if (CurrentUniverseSign  > 0.0) res.Status = 1.0; 
        else res.Status = 2.0; 
        
    if (iWhitehole == 1 && !bIsNakedSingularity && universeoffset>0)
    {
        if (res.Status == 1.0)
            res.Status = 1.0+3.0*float(universeoffset);
        else if (res.Status == 2.0)
            res.Status = 2.0+3.0*float(universeoffset);
    }
    } 
    else {
        res.Status = 0.0; 
        res.EscapeDir = vec3(0.0);
        res.FreqShift = 0.0;
    }
    float energyFlag = (E_conserved >= 0.0) ? 0.0 : 0.2; 
    res.Status       +=  energyFlag;    

    return res;
}


// =============================================================================
// Shadertoy 相机与输出
// =============================================================================
// 相机状态由 A 与 D 传入，Common 不依赖各通道的接线。
bool LoadRayCamera(sampler2D cameraState)
{
    vec3 CamPosWorld = texelFetch(cameraState, ivec2(2, 0), 0).xyz;
    vec3 CamRightWorld = texelFetch(cameraState, ivec2(1, 0), 0).xyz;
    vec3 CamUpWorld = texelFetch(cameraState, ivec2(0, 0), 0).xyz;
    vec4 state = texelFetch(cameraState, ivec2(5, 0), 0);
    vec4 mode = texelFetch(cameraState, ivec2(13, 0), 0);
    if (mode.w != float(CAMERA_MODE + 1)) return false;
    if (mode.w == 3.0 && texelFetch(cameraState, ivec2(6, 0), 0).w > 0.5) {
        return false;
    }
    iUniverseSign = state.y;
    iInWhichUniverse = int(state.z);

    iGameTime = state.x;
    iTimeRate = state.w;
    iBlackHoleTime = iObserverMode == -1 || iObserverMode == 2
        ? texelFetch(cameraState, ivec2(8, 0), 0).w : WORLD_TIME_UNITS_PER_SECOND * iGameTime;
    iCameraVelocity = iObserverMode == 2
        ? texelFetch(cameraState, ivec2(6, 0), 0) : vec4(0.0);
    iCamDataCoordisOutgoing = int(mode.x);
    ie1_up = vec4(0.0); ie2_up = vec4(0.0);
    ie3_up = vec4(0.0);
    iU_up = iObserverMode == 2
          ? texelFetch(cameraState, ivec2(9, 0), 0) : vec4(0.0);

    vec3 CamBackWorld = normalize(cross(CamRightWorld, CamUpWorld));
    mat3 CamRotMat = mat3(CamRightWorld, CamUpWorld, CamBackWorld);
    iInverseCamRot = mat4(CamRotMat);
    iBlackHoleRelativePosRs = iObserverMode == -1
        ? texelFetch(cameraState, ivec2(8, 0), 0)
        : vec4(transpose(CamRotMat) * (-CamPosWorld), 0.0);
    iBlackHoleRelativeDiskNormal = vec4(transpose(CamRotMat) * vec3(0.0, 1.0, 0.0), 0.0);
    iBlackHoleRelativeDiskTangen = vec4(transpose(CamRotMat) * vec3(1.0, 0.0, 0.0), 0.0);
    if (iObserverMode == -1) {
        vec4 e1 = texelFetch(cameraState, ivec2(10, 0), 0);
        vec4 e2 = texelFetch(cameraState, ivec2(11, 0), 0);
        vec4 e3 = texelFetch(cameraState, ivec2(12, 0), 0);
        ie1_up = CamRightWorld.x * e1 + CamRightWorld.y * e2 + CamRightWorld.z * e3;
        ie2_up = CamUpWorld.x * e1 + CamUpWorld.y * e2 + CamUpWorld.z * e3;
        ie3_up = -CamBackWorld.x * e1 - CamBackWorld.y * e2 - CamBackWorld.z * e3;
        iU_up = texelFetch(cameraState, ivec2(9, 0), 0);
    }

    return true;
}

// D 的右侧空白区存放光线数据。每个低分辨率样本只执行一次追踪。
// RGBA32F 的四个通道各保存 30 位；编码只产生正规有限浮点数，避免 NaN 与次正规数被驱动改写。
// RGB 使用非负半精度，alpha 使用 13 位，八面体方向每轴 20 位，频移对数 12 位。
// 状态保留整数与能量符号；超出编码范围的样本标为无效，由 A 完整重算。
int RayAtlasStart() {
    // Bloom 双三次采样最远到 x=max(W/2+2, 5W/16+12)，同时避开纵向模糊的 x<0.52W 区域。
    return max(int(ceil(0.52 * rayResolution.x)) + 4, int(ceil(0.3125 * rayResolution.x)) + 14);
}

ivec2 RayLowSize() {
    return max(ivec2(rayResolution.xy) / RAY_DOWNSAMPLE, ivec2(1));
}

int RayAtlasTileWidth() {
    return max(8, ((int(rayResolution.x) - RayAtlasStart() - 2) / 8) * 8);
}

bool RayPrepassEnabled() {
#if RAY_DOWNSAMPLE == 1 || iGrid != 0 || iDEBUG != 0 || SHADOW_CULL_DEBUG != 0
    // 网格细线可能从低分辨率样本之间穿过；没有交点相位缓冲时保持完整追踪。
    return false;
#else
    if (rayResolution.x * rayResolution.y < float(RAY_MIN_PIXELS)) return false;
    ivec2 lowSize = RayLowSize();
    int tiles = (lowSize.x + RayAtlasTileWidth() - 1) / RayAtlasTileWidth();
    return all(greaterThanEqual(lowSize, ivec2(2)))
        && int(rayResolution.x) - RayAtlasStart() >= RayAtlasTileWidth() + 2
        && tiles * lowSize.y <= int(rayResolution.y);
#endif
}

ivec2 RayAtlasPixel(int index) {
    return ivec2(rayResolution.xy) - ivec2(index + 1, 1);
}

ivec2 RaySamplePixel(ivec2 pixel) {
    int width = RayAtlasTileWidth();
    return ivec2(RayAtlasStart() + pixel.x % width, pixel.y + (pixel.x / width) * RayLowSize().y);
}

float RayStoreBits(uint bits) {
    return uintBitsToFloat((bits & 0x1fffffffu) | ((bits & 0x20000000u) << 2u) | 0x20000000u);
}

uint RayLoadBits(float value) {
    uint bits = floatBitsToUint(value);
    return (bits & 0x1fffffffu) | ((bits >> 2u) & 0x20000000u);
}

vec2 RaySignNotZero(vec2 v) {
    return mix(vec2(-1.0), vec2(1.0), greaterThanEqual(v, vec2(0.0)));
}

vec2 RayEncodeDirection(vec3 dir) {
    dir /= max(dot(abs(dir), vec3(1.0)), 1e-20);
    return (dir.z < 0.0 ? (1.0 - abs(dir.yx)) * RaySignNotZero(dir.xy) : dir.xy) * 0.5 + 0.5;
}

vec3 RayDecodeDirection(vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    vec3 dir = vec3(p, 1.0 - abs(p.x) - abs(p.y));
    dir.xy += RaySignNotZero(dir.xy) * -max(-dir.z, 0.0);
    return normalize(dir);
}

vec4 RayInvalid() {
    return vec4(RayStoreBits(0u), RayStoreBits(0u), RayStoreBits(1023u << 20u), RayStoreBits(0u));
}

vec4 RayPack(TraceResult ray) {
    float whole = round(ray.Status);
    bool sky = int(whole) % 3 != 0;
    uint status = uint(max(whole, 0.0)) * 2u + uint(abs(ray.Status - whole) > 0.1);
    bool invalid = status >= 1023u || whole < 0.0 || any(isnan(ray.AccumColor)) || any(isinf(ray.AccumColor))
        || any(lessThan(ray.AccumColor, vec4(0.0))) || any(greaterThan(ray.AccumColor.rgb, vec3(65504.0)))
        || ray.AccumColor.a > 1.0 || (sky && (any(isnan(ray.EscapeDir)) || any(isinf(ray.EscapeDir))
        || dot(ray.EscapeDir, ray.EscapeDir) < 0.5 || isnan(ray.FreqShift) || isinf(ray.FreqShift)
        || ray.FreqShift < 1.0 / max(iBackShiftMax, 1.0) || ray.FreqShift > max(iBackShiftMax, 1.0)));
    if (invalid) return RayInvalid();
    vec2 oct = RayEncodeDirection(sky ? ray.EscapeDir : vec3(0.0, 0.0, 1.0));
    uvec2 direction = uvec2(round(clamp(oct, 0.0, 1.0) * 1048575.0));
    uint rg = packHalf2x16(ray.AccumColor.rg);
    uint b = packHalf2x16(vec2(ray.AccumColor.b, 0.0));
    uint alpha = uint(round(ray.AccumColor.a * 8191.0));
    float range = max(log2(max(iBackShiftMax, 1.0)), 1e-8);
    uint shift = uint(round(clamp(0.5 + 0.5 * log2(max(ray.FreqShift, 1e-30)) / range, 0.0, 1.0) * 4095.0));
    return vec4(RayStoreBits((rg & 0x7fffu) | ((rg >> 1u) & 0x3fff8000u)),
                RayStoreBits(b | (alpha << 15u) | ((shift >> 10u) << 28u)),
                RayStoreBits(direction.x | (status << 20u)),
                RayStoreBits(direction.y | ((shift & 1023u) << 20u)));
}

TraceResult RayUnpack(vec4 data) {
    uvec4 bits = uvec4(RayLoadBits(data.x), RayLoadBits(data.y), RayLoadBits(data.z), RayLoadBits(data.w));
    uint status = bits.z >> 20u;
    TraceResult ray;
    ray.Status = status == 1023u ? -1.0 : float(status >> 1u) + 0.2 * float(status & 1u);
    ray.AccumColor.rg = unpackHalf2x16((bits.x & 0x7fffu) | ((bits.x & 0x3fff8000u) << 1u));
    ray.AccumColor.b = unpackHalf2x16(bits.y & 0x7fffu).x;
    ray.AccumColor.a = float((bits.y >> 15u) & 8191u) / 8191.0;
    uint shift = (bits.w >> 20u) | ((bits.y >> 28u) << 10u);
    ray.FreqShift = exp2((float(shift) * (2.0 / 4095.0) - 1.0) * log2(max(iBackShiftMax, 1.0)));
    bool sky = int(round(ray.Status)) % 3 != 0 && status != 1023u;
    ray.EscapeDir = sky ? RayDecodeDirection(vec2(bits.z & 1048575u, bits.w & 1048575u) / 1048575.0) : vec3(0.0);
    if (!sky) ray.FreqShift = 0.0;
    ray.CurrentSign = 1.0;
    return ray;
}

TraceResult RayFetch(sampler2D atlas, ivec2 pixel) {
    ivec2 size = RayLowSize();
    pixel = clamp(pixel, ivec2(0), size - 1);
    return RayUnpack(texelFetch(atlas, RaySamplePixel(pixel), 0));
}

bool RayDataBoundary(vec4 a, vec4 b) {
    // 不透明体积与其它状态的交界沿用插值，不把吸积盘表面当作视界边缘。
    if (round(a.w) == 3.0 || round(b.w) == 3.0) return false;
    return abs(a.w - b.w) > 0.1
        || (int(round(a.w)) % 3 != 0 && dot(a.xyz, b.xyz) < RAY_EDGE_COS);
}

bool RayDataCell(vec4 a, vec4 b, vec4 c, vec4 d) {
    return RayDataBoundary(a, b) || RayDataBoundary(a, c) || RayDataBoundary(a, d)
        || RayDataBoundary(b, c) || RayDataBoundary(b, d) || RayDataBoundary(c, d);
}

bool RayNeedsTrace(TraceResult a, TraceResult b, TraceResult c, TraceResult d) {
    if (min(min(a.Status, b.Status), min(c.Status, d.Status)) < 0.0) return true;
    return RayDataCell(vec4(a.EscapeDir, a.Status), vec4(b.EscapeDir, b.Status),
                       vec4(c.EscapeDir, c.Status), vec4(d.EscapeDir, d.Status));
}

TraceResult RayBilinear(TraceResult a, TraceResult b, TraceResult c, TraceResult d, vec2 f) {
    TraceResult ray;
    ray.AccumColor = mix(mix(a.AccumColor, b.AccumColor, f.x), mix(c.AccumColor, d.AccumColor, f.x), f.y);
    vec3 warp = mix(mix(a.EscapeDir * a.FreqShift, b.EscapeDir * b.FreqShift, f.x),
                    mix(c.EscapeDir * c.FreqShift, d.EscapeDir * d.FreqShift, f.x), f.y);
    float skyWeight = mix(mix(float(int(round(a.Status)) % 3 != 0), float(int(round(b.Status)) % 3 != 0), f.x),
                          mix(float(int(round(c.Status)) % 3 != 0), float(int(round(d.Status)) % 3 != 0), f.x), f.y);
    float warpLength = length(warp);
    ray.FreqShift = warpLength / max(skyWeight, 1e-20);
    ray.EscapeDir = warp / max(warpLength, 1e-20);
    ray.Status = round(a.Status) != 3.0 ? a.Status : round(b.Status) != 3.0 ? b.Status
        : round(c.Status) != 3.0 ? c.Status : d.Status;
    // 锚点恰好落在不透明样本上时，不让零权重的天空邻点触发背景采样。
    if (skyWeight <= 0.0 && round(ray.Status) != 0.0) ray.Status = 3.0;
    ray.CurrentSign = 1.0;
    return ray;
}

// 体积与天空光路分别选择滤波；离散状态始终不插值。
#if RAY_VOLUME_INTERPOLATION >= 2 || RAY_SKY_INTERPOLATION >= 2
vec4 RayCubicWeights(float t, int mode) {
    float t2 = t * t, t3 = t2 * t;
    if (mode == 3) return vec4(1.0 - 3.0*t + 3.0*t2 - t3, 4.0 - 6.0*t2 + 3.0*t3,
                              1.0 + 3.0*t + 3.0*t2 - 3.0*t3, t3) / 6.0;
    return vec4(-t + 2.0*t2 - t3, 2.0 - 5.0*t2 + 3.0*t3,
                 t + 4.0*t2 - 3.0*t3, -t2 + t3) * 0.5;
}
#endif

TraceResult RayInterpolate(sampler2D atlas, ivec2 base, TraceResult a, TraceResult b,
                          TraceResult c, TraceResult d, vec2 f) {
    TraceResult ray = RayBilinear(a, b, c, d, f);
#if RAY_VOLUME_INTERPOLATION == 0 || RAY_SKY_INTERPOLATION == 0
    TraceResult nearest;
    if (f.y < 0.5) {
        if (f.x < 0.5) nearest = a; else nearest = b;
    } else {
        if (f.x < 0.5) nearest = c; else nearest = d;
    }
    #if RAY_VOLUME_INTERPOLATION == 0
        ray.AccumColor = nearest.AccumColor;
    #endif
    #if RAY_SKY_INTERPOLATION == 0
        ray.EscapeDir = nearest.EscapeDir;
        ray.FreqShift = nearest.FreqShift;
        ray.Status = nearest.Status;
    #endif
#endif
#if RAY_VOLUME_INTERPOLATION >= 2 || RAY_SKY_INTERPOLATION >= 2
    // 末端锚点间距可能不均匀；边缘继续使用双线性，避免用等距三次核外推。
    if (any(greaterThanEqual(base, RayLowSize() - 3))) return ray;
    vec4 color = vec4(0.0);
    vec3 warp = vec3(0.0);
    vec4 cx = RayCubicWeights(f.x, RAY_VOLUME_INTERPOLATION);
    vec4 cy = RayCubicWeights(f.y, RAY_VOLUME_INTERPOLATION);
    vec4 wx = RayCubicWeights(f.x, RAY_SKY_INTERPOLATION);
    vec4 wy = RayCubicWeights(f.y, RAY_SKY_INTERPOLATION);
    bool compatible = true;
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            TraceResult sampleRay;
            if (x == 1 && y == 1) sampleRay = a;
            else if (x == 2 && y == 1) sampleRay = b;
            else if (x == 1 && y == 2) sampleRay = c;
            else if (x == 2 && y == 2) sampleRay = d;
            else sampleRay = RayFetch(atlas, base + ivec2(x - 1, y - 1));
            // 外圈遇到未完成光路、不同宇宙或不透明表面时退回双线性，不扩大重算环。
            compatible = compatible && sampleRay.Status >= 0.0
                && abs(sampleRay.Status - a.Status) < 0.1
                && (int(round(a.Status)) % 3 == 0 || dot(sampleRay.EscapeDir, a.EscapeDir) >= RAY_EDGE_COS);
            #if RAY_VOLUME_INTERPOLATION >= 2
                color += sampleRay.AccumColor * (cx[x] * cy[y]);
            #endif
            #if RAY_SKY_INTERPOLATION >= 2
                warp += sampleRay.EscapeDir * sampleRay.FreqShift * (wx[x] * wy[y]);
            #endif
        }
    }
    if (compatible) {
        #if RAY_VOLUME_INTERPOLATION == 2
            // Catmull-Rom 的负权重可能产生负亮度或密度过冲；限于中心四点范围。
            color = clamp(color, min(min(a.AccumColor, b.AccumColor), min(c.AccumColor, d.AccumColor)),
                                 max(max(a.AccumColor, b.AccumColor), max(c.AccumColor, d.AccumColor)));
        #endif
        #if RAY_VOLUME_INTERPOLATION >= 2
            ray.AccumColor = color;
        #endif
        #if RAY_SKY_INTERPOLATION >= 2
            if (int(round(a.Status)) % 3 != 0) {
                #if RAY_SKY_INTERPOLATION == 2
                    vec3 va = a.EscapeDir * a.FreqShift, vb = b.EscapeDir * b.FreqShift;
                    vec3 vc = c.EscapeDir * c.FreqShift, vd = d.EscapeDir * d.FreqShift;
                    warp = clamp(warp, min(min(va, vb), min(vc, vd)), max(max(va, vb), max(vc, vd)));
                #endif
                float amplitude = length(warp);
                if (amplitude > 1e-20) {
                    ray.EscapeDir = warp / amplitude;
                    ray.FreqShift = clamp(amplitude, min(min(a.FreqShift, b.FreqShift), min(c.FreqShift, d.FreqShift)),
                                                   max(max(a.FreqShift, b.FreqShift), max(c.FreqShift, d.FreqShift)));
                }
            }
        #endif
    }
#endif
    return ray;
}
