/**
 *                  _______  ___  ___       ___           ___
 *                 /       ||   \/   |     /   \         /   \
 *                |   (---- |  \  /  |    /  ^  \       /  ^  \
 *                 \   \    |  |\/|  |   /  /_\  \     /  /_\  \
 *              ----)   |   |  |  |  |  /  _____  \   /  _____  \
 *             |_______/    |__|  |__| /__/     \__\ /__/     \__\
 *
 *                               E N H A N C E D
 *       S U B P I X E L   M O R P H O L O G I C A L   A N T I A L I A S I N G
 *
 *                               for ReShade 3.0
 */

// -------------------------------------------------------------------------------

uniform int SMAA_EdgeDetectionType <
	ui_type = "combo";
	ui_items = "Luminance edge detection\0Color edge detection\0Depth edge detection\0";
> = 1;

uniform float SMAA_Threshold <
	ui_type = "drag";
	ui_min = 0.05; ui_max = 0.20; ui_step = 0.02;
	ui_tooltip = "Edge detection threshold. If SMAA misses some edges try lowering this slightly.";
> = 0.10;
uniform int SMAA_MaxSearchSteps <
	ui_min = 0; ui_max = 98;
	ui_tooltip = "Determines the radius SMAA will search for aliased edges.";
> = 98;
uniform int SMAA_MaxSearchStepsDiagonal <
	ui_min = 0; ui_max = 16;
	ui_tooltip = "Determines the radius SMAA will search for diagonal aliased edges";
> = 16;
uniform int SMAA_CornerRounding <
	ui_type = "drag";
	ui_min = 0; ui_max = 100;
	ui_tooltip = "Determines the percent of anti-aliasing to apply to corners. 0 seems to affect fine text the least so it's the default.";
> = 0;

uniform bool SMAA_DebugOutput <
	ui_tooltip = "Display the contents of the 'edgeTex' and 'blendTex' buffers.";
> = false;

// -------------------------------------------------------------------------------

#define SMAA_RT_METRICS float4(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT, BUFFER_WIDTH, BUFFER_HEIGHT)
#define SMAA_CUSTOM_SL 1
#define SMAA_PRESET_CUSTOM 1

#define SMAA_THRESHOLD SMAA_Threshold
#define SMAA_MAX_SEARCH_STEPS SMAA_MaxSearchSteps
#define SMAA_MAX_SEARCH_STEPS_DIAG SMAA_MaxSearchStepsDiagonal
#define SMAA_CORNER_ROUNDING SMAA_CornerRounding

#define SMAATexture2D(tex) sampler tex
#define SMAATexturePass2D(tex) tex
#define SMAASampleLevelZero(tex, coord) tex2Dlod(tex, float4(coord, coord))
#define SMAASampleLevelZeroPoint(tex, coord) SMAASampleLevelZero(tex, coord)
#define SMAASampleLevelZeroOffset(tex, coord, offset) tex2Dlodoffset(tex, float4(coord, coord), offset)
#define SMAASample(tex, coord) tex2D(tex, coord)
#define SMAASamplePoint(tex, coord) SMAASample(tex, coord)
#define SMAASampleOffset(tex, coord, offset) tex2Doffset(tex, coord, offset)
#define SMAA_BRANCH [branch]
#define SMAA_FLATTEN [flatten]

#if (__RENDERER__ == 0xb000 || __RENDERER__ == 0xb100)
	#define SMAAGather(tex, coord) tex2Dgather(tex, coord, 0)
#endif

#include "SMAA.fxh"
#include "ReShade.fxh"

// Textures

texture edgesTex
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA8;
};
texture blendTex
{
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA8;
};

texture areaTex < source = "AreaTex.dds"; >
{
	Width = 160;
	Height = 560;
	Format = RG8;
};
texture searchTex < source = "SearchTex.dds"; >
{
	Width = 64;
	Height = 16;
	Format = R8;
};

// Samplers

sampler colorGammaSampler
{
	Texture = ReShade::BackBufferTex;
	AddressU = Clamp; AddressV = Clamp;
	MipFilter = Point; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = false;
};
sampler colorLinearSampler
{
	Texture = ReShade::BackBufferTex;
	AddressU = Clamp; AddressV = Clamp;
	MipFilter = Point; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = true;
};
sampler edgesSampler
{
	Texture = edgesTex;
	AddressU = Clamp; AddressV = Clamp;
	MipFilter = Linear; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = false;
};
sampler blendSampler
{
	Texture = blendTex;
	AddressU = Clamp; AddressV = Clamp;
	MipFilter = Linear; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = false;
};
sampler areaSampler
{
	Texture = areaTex;
	AddressU = Clamp; AddressV = Clamp; AddressW = Clamp;
	MipFilter = Linear; MinFilter = Linear; MagFilter = Linear;
	SRGBTexture = false;
};
sampler searchSampler
{
	Texture = searchTex;
	AddressU = Clamp; AddressV = Clamp; AddressW = Clamp;
	MipFilter = Point; MinFilter = Point; MagFilter = Point;
	SRGBTexture = false;
};

// Vertex shaders

void SMAAEdgeDetectionWrapVS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float4 offset[3] : TEXCOORD1)
{
	PostProcessVS(id, position, texcoord);
	SMAAEdgeDetectionVS(texcoord, offset);
}
void SMAABlendingWeightCalculationWrapVS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float2 pixcoord : TEXCOORD1,
	out float4 offset[3] : TEXCOORD2)
{
	PostProcessVS(id, position, texcoord);
	SMAABlendingWeightCalculationVS(texcoord, pixcoord, offset);
}
void SMAANeighborhoodBlendingWrapVS(
	in uint id : SV_VertexID,
	out float4 position : SV_Position,
	out float2 texcoord : TEXCOORD0,
	out float4 offset : TEXCOORD1)
{
	PostProcessVS(id, position, texcoord);
	SMAANeighborhoodBlendingVS(texcoord, offset);
}

// Pixel shaders

float2 SMAAEdgeDetectionWrapPS(
	float4 position : SV_Position,
	float2 texcoord : TEXCOORD0,
	float4 offset[3] : TEXCOORD1) : SV_Target
{
	if (SMAA_EdgeDetectionType == 0)
		return SMAALumaEdgeDetectionPS(texcoord, offset, colorGammaSampler);
	if (SMAA_EdgeDetectionType == 2)
		return SMAADepthEdgeDetectionPS(texcoord, offset, ReShade::DepthBuffer);

	return SMAAColorEdgeDetectionPS(texcoord, offset, colorGammaSampler);
}
float4 SMAABlendingWeightCalculationWrapPS(
	float4 position : SV_Position,
	float2 texcoord : TEXCOORD0,
	float2 pixcoord : TEXCOORD1,
	float4 offset[3] : TEXCOORD2) : SV_Target
{
	return SMAABlendingWeightCalculationPS(texcoord, pixcoord, offset, edgesSampler, areaSampler, searchSampler, 0.0);
}

float3 SMAANeighborhoodBlendingWrapPS(
	float4 position : SV_Position,
	float2 texcoord : TEXCOORD0,
	float4 offset : TEXCOORD1) : SV_Target
{
	if (SMAA_DebugOutput)
	{
		return texcoord.x < texcoord.y ? tex2D(edgesSampler, texcoord).rgb : tex2D(blendSampler, texcoord).rgb;
	}

	return SMAANeighborhoodBlendingPS(texcoord, offset, colorLinearSampler, blendSampler).rgb;
}

// Rendering passes

technique SMAA
{
	pass EdgeDetectionPass
	{
		VertexShader = SMAAEdgeDetectionWrapVS;
		PixelShader = SMAAEdgeDetectionWrapPS;
		RenderTarget = edgesTex;
		ClearRenderTargets = true;

		StencilEnable = true;
		StencilPass = REPLACE;
		StencilRef = 1;
	}
	pass BlendWeightCalculationPass
	{
		VertexShader = SMAABlendingWeightCalculationWrapVS;
		PixelShader = SMAABlendingWeightCalculationWrapPS;
		RenderTarget = blendTex;
		ClearRenderTargets = true;

		StencilEnable = true;
		StencilPass = KEEP;
		StencilFunc = EQUAL;
		StencilRef = 1;
	}
	pass NeighborhoodBlendingPass
	{
		VertexShader = SMAANeighborhoodBlendingWrapVS;
		PixelShader = SMAANeighborhoodBlendingWrapPS;

		StencilEnable = false;
		SRGBWriteEnable = true;
	}
}