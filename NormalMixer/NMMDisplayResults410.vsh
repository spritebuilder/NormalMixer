#version 410

uniform vec2 positionScale;
uniform vec2 positionOffset;

in vec2 inPosition;
in vec2 inTexCoord;

out vec2 fragTexCoord;

void main()
{
    gl_Position = vec4(inPosition * positionScale + positionOffset, 0.0, 1.0);
    fragTexCoord.x = inTexCoord.x;
    fragTexCoord.y = 1.0 - inTexCoord.y;
}