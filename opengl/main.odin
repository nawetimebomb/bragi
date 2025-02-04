package main

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

    for !glfw.WindowShouldClose(window) {
        process_input()

        gl.ClearColor(0.0, 0.13, 0.15, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)
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
