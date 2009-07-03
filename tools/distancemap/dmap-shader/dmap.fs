uniform sampler2D directionMap;
uniform sampler2D angleMap;

const float kThreshold = 0.5;
const float kInnerThreshold = kThreshold + 0.01;
const float kOuterThreshold = kThreshold - 0.1;
const float kFallbackAAFactor = 0.03;
const float kAABlurFactor = 1.5;

const vec4 kBlack = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 kWhite = vec4(1.0);
const vec4 kRed = vec4(1.0, 0.0, 0.0, 1.0);
const vec4 kBlue = vec4(0.0, 0.0, 1.0, 1.0);


float AntiAliasFactor()
{
	return length(fwidth(gl_TexCoord[0].xy)) * 2.0;
}


float DistanceMap(sampler2D texture, vec2 texCoords, float threshold)
{
	float dmap = texture2D(texture, texCoords).r;
	
	// Fake anti-aliasing with a hermite blur.
	// The fwidth() term lets us scale this appropriately for the screen.
	vec2 fw = fwidth(texCoords);
	float aaFactor = (fw.x + fw.y) * kAABlurFactor;
	// If fwidth() doesn't provide useful data, use a fixed blur instead.
	// Setting kFallbackAAFactor to zero gives you aliased output in the fallback case.
	aaFactor = (aaFactor == 0.0) ? kFallbackAAFactor : aaFactor;
	return smoothstep(threshold - aaFactor, threshold + aaFactor, dmap);
}


void main()
{
	float inner = DistanceMap(directionMap, gl_TexCoord[0].xy, kInnerThreshold);
	float outer = DistanceMap(directionMap, gl_TexCoord[0].xy, kOuterThreshold);
	
	vec4 color = mix(kBlack, kRed, inner);
	color = mix(kWhite, color, outer);
	
	gl_FragColor = color;
}
