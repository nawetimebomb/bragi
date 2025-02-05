package main

import    "core:fmt"
import    "vendor:glfw"
import gl "vendor:OpenGL"
import tt "vendor:stb/truetype"

BRAGI_TITLE   :: "Bragi"
BRAGI_VERSION :: 0

GL_VERSION_MAJOR :: 3
GL_VERSION_MINOR :: 3
GL_VSYNC_ENABLED :: 1

Window_Type :: glfw.WindowHandle

window:        Window_Type
window_height: i32 = 600
window_width:  i32 = 800
window_x:      i32
window_y:      i32
window_title:  cstring = BRAGI_TITLE

main :: proc() {
    glfw.Init()
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    when ODIN_OS == .Darwin {
        glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, true)
    }

    window = glfw.CreateWindow(window_width, window_height, window_title, nil, nil)
    assert(window != nil, "Failed to create window")
    glfw.MakeContextCurrent(window)
    glfw.SwapInterval(GL_VSYNC_ENABLED)
    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)
    gl.Viewport(0, 0, window_width, window_height)
    glfw.SetFramebufferSizeCallback(window, handle_framebuffer_resize)

    /*****************************************************
    *              Stuff just for testing                *
    ******************************************************/
    vertexShaderSource : cstring = "#version 330 core\nlayout (location = 0) in vec3 aPos;\nvoid main() {\ngl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);\n}"
    vertexShader := gl.CreateShader(gl.VERTEX_SHADER)
    gl.ShaderSource(vertexShader, 1, &vertexShaderSource, nil)
    gl.CompileShader(vertexShader)

    success: i32
    gl.GetShaderiv(vertexShader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        fmt.println("ERROR COMPILING SHADER")
    }

    fragmentShaderSource : cstring = "#version 330 core\nout vec4 FragColor;\nvoid main() {\nFragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);\n}"
    fragmentShader := gl.CreateShader(gl.FRAGMENT_SHADER)
    gl.ShaderSource(fragmentShader, 1, &fragmentShaderSource, nil)
    gl.CompileShader(fragmentShader)

    gl.GetShaderiv(fragmentShader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        fmt.println("ERROR COMPILING SHADER")
    }

    shaderProgram := gl.CreateProgram()
    gl.AttachShader(shaderProgram, vertexShader)
    gl.AttachShader(shaderProgram, fragmentShader)
    gl.LinkProgram(shaderProgram)

    gl.GetProgramiv(shaderProgram, gl.LINK_STATUS, &success)

    if success == 0 {
        fmt.println("ERROR LINKING PROGRAM")
    }

    gl.DeleteShader(vertexShader)
    gl.DeleteShader(fragmentShader)

    vertices := []f32{ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, 0.0, 0.5, 0.0 }
    VBO, VAO: u32
    gl.GenVertexArrays(1, &VAO)
    gl.GenBuffers(1, &VBO)

    gl.BindVertexArray(VAO)

    gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), raw_data(vertices), gl.STATIC_DRAW)

    gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), uintptr(0))
    gl.EnableVertexAttribArray(0)

    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    gl.BindVertexArray(0)

    for !glfw.WindowShouldClose(window) {
        process_input()

        gl.ClearColor(0.0, 0.13, 0.15, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(shaderProgram)
        gl.BindVertexArray(VAO)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)

        glfw.SwapBuffers(window)
        glfw.PollEvents()
        free_all(context.temp_allocator)
    }

    glfw.DestroyWindow(window)
    glfw.Terminate()
}

process_input :: proc() {
    if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
        glfw.SetWindowShouldClose(window, true)
    }
}

handle_framebuffer_resize :: proc "c" (window: Window_Type, width, height: i32) {
    window_width  = width
    window_height = height
    gl.Viewport(0, 0, width, height)
}
