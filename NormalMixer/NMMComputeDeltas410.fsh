#version 410


uniform float normalScale;
uniform sampler2D baseTexture;
uniform sampler2D detailTexture;

in vec2 fragTexCoord;
out vec4 outColor;

vec3 unpack_normal(vec3 packed_normal)
{
    return packed_normal * 2.0 - 1.0;
}

vec3 pack_normal(vec3 unpacked_normal)
{
    return (unpacked_normal + 1.0) * 0.5;
}

void main()
{
    // Unpack the detail normal vector from the detail normal map.
    vec4 detailColor = texture(detailTexture, fragTexCoord);
    vec3 detailNormal = unpack_normal(detailColor.xyz);

    // Unpack the base normal vector from the detail normal map.
    vec4 baseColor = texture(baseTexture, fragTexCoord);
    vec3 baseNormal = normalize(unpack_normal(baseColor.xyz));

    // Construct the basis vectors for the base normal map coordinate
    // system.
    vec3 baseRight, baseUp;
    if (dot(baseNormal, vec3(0,1,0)) > 0.95)
    {
        // If the supplied normal is too close to vec3(0,1,0) then start by
        // crossing it with vec3(1,0,0) to compute an initial up vector. Then
        // cross up with normal to compute the right vector.
        baseUp = normalize(cross(baseNormal, vec3(1,0,0)));
        baseRight = normalize(cross(baseUp, baseNormal));
    }
    else
    {
        // If the supplied normal is not close to vec3(0,1,0) then start by
        // crossing vec3(0,1,0) with the normal to compute the right vector.
        // Then cross normal with right to compute the up vector.
        baseRight = normalize(cross(vec3(0,1,0), baseNormal));
        baseUp = normalize(cross(baseNormal, baseRight));
    }
    
    // Reorient the detail normal into the base normal map coordinate
    // system.
    vec3 remappedNormal = baseRight * detailNormal.x + baseUp * detailNormal.y + baseNormal * detailNormal.z;

    outColor = vec4(pack_normal(normalize(remappedNormal)), baseColor.a);
}