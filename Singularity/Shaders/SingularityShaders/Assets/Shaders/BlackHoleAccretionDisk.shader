﻿Shader "Singularity/BlackHoleAccretionDisk"
{
    Properties
    {
        CubeMap ("Cubemap", CUBE) = "" {}
        //AccretionDisk ("AccretionDisk", 2D) = "white" {} 
    }
    SubShader
    {
			Tags {"QUEUE"="Geometry+1" "IgnoreProjector"="True" }

    	 	ZWrite Off
    	 	cull Front
    	 
    		//Blend DstColor Zero

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma target 3.0

            #pragma multi_compile ACCRETION_DISK_OFF ACCRETION_DISK_ON
            #pragma multi_compile RADIAL_DISK_MAPPING_OFF RADIAL_DISK_MAPPING_ON

            #include "UnityCG.cginc"

            #define ID_BLACKHOLE 0
			#define ID_BLACKHOLE_DISK 1

			//uniform float4 blackhole;
			uniform float blackHoleRadius;
			uniform float gravity;

			uniform samplerCUBE CubeMap;
			uniform sampler2D AccretionDisk;
			//uniform sampler2D RadialAccretionDisk;

			uniform float3 diskNormal;
			uniform float diskInnerRadius;
			uniform float diskOuterRadius;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex  : SV_POSITION;
                float4 worldPos : TEXCOORD0;
                float4 blackHoleOrigin : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.blackHoleOrigin = mul(unity_ObjectToWorld, float4(0,0,0,1));
                return o;
            }


			float3 accretionDiskColor(float3 pos, float3 base1, float3 base2, float3 blackHoleOrigin)
			{

#if defined (RADIAL_DISK_MAPPING_ON)

				//TODO: make this rotate, move TWOPI to defines

			  float TWOPI = 6.28318530718;
			  pos = pos - blackHoleOrigin;
			  float dist = length(pos);

			  // Important! Scale radii according to black hole
			  float v = clamp((dist - diskInnerRadius) / (diskOuterRadius - diskInnerRadius), 0.0, 1.0);

//			  float3 base = cross(blackholeDisk.xyz, float3(0.0, 0.0, 1.0));
			  float angle = acos(dot(normalize(base1), normalize(pos)));
			  if (dot(cross(base1, pos), diskNormal) < 0.0) angle = -angle;

			  float u = 0.5 - angle / TWOPI;

			  float3 color = tex2Dlod(AccretionDisk, float4(u, v,0.0,0.0)).rgb;

			  return color;
#else
				float u = dot (base1,normalize(pos)) * (length(pos)-diskInnerRadius) / (diskOuterRadius-diskInnerRadius);
				float v = dot (base2,normalize(pos)) * (length(pos)-diskInnerRadius) / (diskOuterRadius-diskInnerRadius);

				float2 UV = float2(u,v);

				//can simplify these and move them out of this loop
				float sinX = sin ( -_Time.y * 3 );
            	float cosX = cos ( -_Time.y * 3 );

				float2x2 rotationMatrix = float2x2( cosX, -sinX, sinX, cosX);
				UV = mul(rotationMatrix, UV);

				UV = 0.5 - 0.5 * UV;
				UV = clamp (UV,0.0,1.0);

				float4 color = tex2Dlod(AccretionDisk, float4(UV,0.0,0.0));

				return color.rgb*color.a;
#endif
			}

			float sphereDistance(float3 rayPosition, float3 rayDirection, float4 sphere)
			{
			  float3 v;
			  float p, d;
			  v = rayPosition - sphere.xyz;
			  p = dot(rayDirection, v);
			  d = p * p + sphere.w * sphere.w - dot(v, v);

			  return d < 0.0 ? -1.0 : -p - sqrt(d);
			}

			//simplify this also
			void testDistance(int i, float distance, inout float currentDistance, inout int currentObject, float maxDistance)
			{
			  float EPSILON = 0.0001;

			  if (distance >= EPSILON && distance < currentDistance && distance < maxDistance)
			  {
			    currentDistance = distance;
			    currentObject = i;
			  }
			}

			//simplify this
			float ringDistance(float3 rayPosition, float3 rayDirection, float3 blackHoleOrigin)
			{
			  float EPSILON = 0.0001;

			  float denominator = dot(rayDirection, diskNormal);
			  float constant = -dot(blackHoleOrigin, diskNormal);
			  float distanceToCenter;
			  if (abs(denominator) < EPSILON)
			  {
			    return -1.0;
			  }
			  else
			  {
			    float t = -(dot(rayPosition, diskNormal) + constant) / denominator;
			    if (t < 0.0) return -1.0;

			    float3 intersection = rayPosition + t * rayDirection;
			    distanceToCenter = length(intersection - blackHoleOrigin);
			    if (distanceToCenter >= diskInnerRadius && distanceToCenter <= diskOuterRadius)
			    {
			      return t;
			    }
			    return -1.0;
			  }
			}

//			float LinePlaneIntersection(float3 rayPosition, float3 rayDirection)
//			{
//				float tlength;
//				float dotNumerator;
//				float dotDenominator;
//					
//				float3 intersectVector;
//				float3 intersection = 0.0;
//
//				//calculate the distance between the linePoint and the line-plane intersection point
//				dotNumerator = dot((blackHoleOrigin - rayPosition), diskNormal);
//				dotDenominator = dot(rayDirection, diskNormal);
//
//				//line and plane are not parallel
//				if(dotDenominator != 0.0f)
//				{
//					tlength =  dotNumerator / dotDenominator;
//			  		intersection= (tlength > 0.0) ? rayPosition + rayDirection * tlength : rayPosition;
//			  		float distanceToCenter = length(intersection - blackHoleOrigin);
//
//			  		return (tlength > 0.0 && distanceToCenter >= diskInnerRadius && distanceToCenter <= diskOuterRadius) ? tlength : -1.0; //or -1?
//				}
//				else
//				{
//					return -1.0;
//				}
//
//				//return intersection;
//			}

			float3 raytrace(float3 rayPosition, float3 rayDirection, float3 blackHoleOrigin)
			{
				float lightSpeed = 0.2; // Not actually representing light speed :P

				float INFINITY = 1000000.0;
					
				float currentDistance = INFINITY;
				int   currentObject = -1;
				float3  hitPosition;

				float stepSize, rayDistance;
				float3 gravityVector, rayAccel;
				float objectDistance;

				float3 rayNextPosition = rayPosition;

				float4 color = float4(0.0, 0.0, 0.0, 1.0);

#if defined (ACCRETION_DISK_ON)
				//acretion disk base vectors
				float3 base1 = normalize(cross(diskNormal, diskNormal.zxy)); //move this to plugin precomputation, check if 2nd vector is equal to first and re-change it
				float3 base2 = normalize(cross(base1, diskNormal)); 		 //move this to precomputation
#endif

				float blackHoleHit = 0.0;

				for (int i = 0; i < 35; i++)
				//for (int i = 0; i < 70; i++)
				{
					currentObject = -1;
			  		currentDistance = INFINITY;

			  		// Bend the light towards the black hole
			  		gravityVector = blackHoleOrigin - rayPosition;
			  		rayDistance = length(gravityVector);

			  		// 0.05: rate of smaller steps when approaching blackhole
			  		stepSize = rayDistance - (blackHoleRadius *0.05);

			  		rayAccel = normalize(gravityVector) * gravity / (rayDistance * rayDistance);

			  		//rayDirection=normalize(rayDirection * lightSpeed + rayAccel * stepSize);
			  		rayDirection=normalize(rayDirection * lightSpeed * stepSize + rayAccel * stepSize);
					 	
			  		objectDistance = sphereDistance(rayPosition, rayDirection, float4(blackHoleOrigin, blackHoleRadius * 1.0));
			  		testDistance(ID_BLACKHOLE, objectDistance, currentDistance, currentObject, lightSpeed*stepSize);

#if defined (ACCRETION_DISK_ON)
			  		objectDistance = ringDistance(rayPosition, rayDirection, blackHoleOrigin);
			  		//objectDistance = LinePlaneIntersection(rayPosition, rayDirection);

			  		testDistance(ID_BLACKHOLE_DISK, objectDistance, currentDistance, currentObject, lightSpeed*stepSize);
#endif
			  		// Check if we hit any object, and if so, stop integrating
			  		if (currentObject != -1 && currentDistance <= rayDistance)
			  		{
#if defined (ACCRETION_DISK_ON)
			  		   //But if it's something transparent, get its color, and continue
			  		  if (currentObject == ID_BLACKHOLE_DISK)
			  		  {
			  		    hitPosition = rayPosition + rayDirection * currentDistance;
			  		    color.rgb += (1.0-color.rgb) * accretionDiskColor(hitPosition,base1,base2,blackHoleOrigin).rgb; //soft blend them
			  		    currentObject = -1;
			  		  }
			  		  else
#endif
			  		  {
			  		  //add && currentDistance <= rayDistance
			  		    break;
			  		  }
			  		}

					//move forward
					rayPosition += lightSpeed * stepSize * rayDirection;
				}

				if (currentObject != ID_BLACKHOLE && length(rayPosition) > blackHoleRadius )
				{
					float3 cubeMapColor = texCUBE(CubeMap, rayDirection);
					color.rgb += (1.0 - color.rgb) * cubeMapColor;
					//consider enabling/disabling mipMaps and texcube Bias (possibly negative, to strike balance between jittering and clarity
					//maybe even a crisper image when the light is blueshifted, to simulate distant stars becoming clearer, but check if KSP does mipMaps on background skybox first
				}			

				return color;
			}

            float4 frag (v2f i) : SV_Target
            {
            	i.worldPos.xyz/=i.worldPos.w;
            	float3 viewDir = normalize(i.worldPos.xyz-_WorldSpaceCameraPos);

  				float3 color = raytrace(_WorldSpaceCameraPos, viewDir, i.blackHoleOrigin.xyz/i.blackHoleOrigin.w);

  				return float4(color, 1.0);
            }
            ENDCG
        }
    }
}