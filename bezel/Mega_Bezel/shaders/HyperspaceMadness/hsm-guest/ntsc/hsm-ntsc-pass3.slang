#version 450

// NTSC-Adaptive
// based on Themaister's NTSC shader


layout(std140, set = 0, binding = 0) uniform UBO
{
   mat4 MVP;
   vec4 OutputSize;
   vec4 OriginalSize;
   vec4 SourceSize;
   vec4 DerezedPassSize;
   float ntsc_sharp;
   float ntsc_shape;
   float blendMode;
} global;

#pragma parameter ntsc_sharp "          NTSC Sharpness (Negative: Adaptive)" 0.0 -10.0 10.0 0.50
#pragma parameter ntsc_shape "          NTSC Sharpness Shape" 0.75 0.5 1.0 0.05
#pragma parameter blendMode  "          NTSC Blend Mode (Main Mode Control)" 1.0 0.0 1.0 1.0 

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord - vec2(0.25 / global.SourceSize.x, 0.0); // Compensate for decimate-by-2.
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D NPass1;
layout(set = 0, binding = 4) uniform sampler2D PrePass0;

float fetch_offset(float offset, float one_x)
{
   return texture(NPass1, vTexCoord + vec2((offset) * (one_x), 0.0)).x;
}

const mat3 yiq2rgb_mat = mat3(
   1.0, 0.956, 0.6210,
   1.0, -0.2720, -0.6474,
   1.0, -1.1060, 1.7046);

vec3 yiq2rgb(vec3 yiq)
{
   return yiq * yiq2rgb_mat;
}

const mat3 yiq_mat = mat3(
      0.2989, 0.5870, 0.1140,
      0.5959, -0.2744, -0.3216,
      0.2115, -0.5229, 0.3114
);

vec3 rgb2yiq(vec3 col)
{
   return col * yiq_mat;
}
   

void main()
{
   vec2 offsetx = vec2(0.5 * global.DerezedPassSize.z, 0.0);
   vec2 texcoord = vTexCoord + vec2(0.25 * global.SourceSize.z, 0.0);
   
   vec3 l1  = texture(Source, texcoord +      offsetx).xyz;
   vec3 l2  = texture(Source, texcoord -      offsetx).xyz;
   vec3 l3  = texture(Source, texcoord + 0.50*offsetx).xyz;
   vec3 l4  = texture(Source, texcoord - 0.50*offsetx).xyz;
   vec3 ref = texture(Source, texcoord).xyz;
   
   float lum1 = texture(NPass1, vTexCoord).a;
   float lum2 = max(ref.x, 0.0);

   float dif = max(max(abs(l1.x-l2.x), abs(l1.y-l2.y)), max(abs(l1.z-l2.z), abs(l1.x*l1.x-l2.x*l2.x)));
   float dff = max(max(abs(l3.x-l4.x), abs(l3.y-l4.y)), max(abs(l3.z-l4.z), abs(l3.x*l3.x-l4.x*l4.x)));   
   
   float lc = (1.0-smoothstep(0.10, 0.20, abs(lum2-lum1)))*pow(dff, 0.125);

   float sweight = smoothstep(0.05-0.03*lc, 0.45 - 0.40*lc, dif);
   
   vec3 signal = ref;

   if (abs(global.ntsc_sharp) > -0.1)
   {
	  float lummix = mix(lum2, lum1, 0.1*abs(global.ntsc_sharp));
      float lm1 =  mix(lum2*lum2, lum1*lum1, 0.1*abs(global.ntsc_sharp)); lm1 = sqrt(lm1);
      float lm2 =  mix(sqrt(lum2), sqrt(lum1), 0.1*abs(global.ntsc_sharp)); lm2 = lm2*lm2;
	  
	  float k1 = abs(lummix - lm1) + 0.00001;
	  float k2 = abs(lummix - lm2) + 0.00001;
	  
	  lummix = min((k2*lm1 + k1*lm2)/(k1+k2), 1.0);
	  
	  signal.x = mix(lum2, lummix, smoothstep(0.25, 0.4, pow(dff, 0.125)));
	  signal.x = min(signal.x, max(global.ntsc_shape*signal.x, lum2)); 	  
   }   
   else    signal.x = clamp(signal.x, -1.0, 1.0);

   vec3 rgb = signal;	
   if (global.ntsc_sharp < -0.1)
   {
      rgb.x = mix(ref.x, rgb.x, sweight);
   }
  
   rgb = clamp(yiq2rgb(rgb), 0.0, 1.0);  
  
   if (global.blendMode < 0.5)
   {
      vec3 orig = texture(PrePass0, vTexCoord).rgb;
      rgb = normalize(rgb + 0.00001) * min(length(rgb), length(orig));    
   }
   
   FragColor = vec4(rgb, 1.0);
}  
