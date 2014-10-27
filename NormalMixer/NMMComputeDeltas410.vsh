#version 410

in vec2 inPosition;
in vec2 inTexCoord;

out vec2 fragTexCoord;

void main()
{
    gl_Position = vec4(inPosition * 2.0 - 1.0, 0.0, 1.0);
    fragTexCoord = inTexCoord;
}