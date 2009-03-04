uniform sampler2D tex;

const float kThreshold = 0.5;
const float kFallbackAAFactor = 0.03;

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
	float dmap = texture2D(tex, texCoords).r;
	
	// Fake anti-aliasing with a hermite blur.
	// The fwidth() term lets us scale this appropriately for the screen.
	vec2 fw = fwidth(texCoords);
	float aaFactor = (fw.x + fw.y) * 1.5;
	// If fwidth() doesn't provide useful data, use a fixed blur instead.
	// Setting kFallbackAAFactor to zero gives you aliased output in the fallback case.
	aaFactor = (aaFactor == 0.0) ? kFallbackAAFactor : aaFactor;
	return smoothstep(threshold - aaFactor, threshold + aaFactor, dmap);
}


void main()
{
#if 1
	float inner = DistanceMap(tex, gl_TexCoord[0].xy, kThreshold + 0.01);
	float outer = DistanceMap(tex, gl_TexCoord[0].xy, kThreshold - 0.02);
	
	vec4 decalColor = mix(kBlack, kRed, inner);
	decalColor = mix(kWhite, decalColor, outer);
#else
	float mask = DistanceMap(tex, gl_TexCoord[0].xy, kThreshold);
	vec4 decalColor = mix(kWhite, kBlack, mask);
#endif
	
	gl_FragColor = decalColor;
}
