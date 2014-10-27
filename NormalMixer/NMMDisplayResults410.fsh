#version 410

uniform sampler2D baseTexture;

in vec2 fragTexCoord;
out vec4 outColor;

void main()
{
    outColor = texture(baseTexture, fragTexCoord);
}