#version 300

void main() {
    // 01

    float x = float(gl_VertexID & 1);
    float y = float((gl_VertexID >> 1) & 1);
    gl_Position = vec2(x, y) - 0.5;
}
