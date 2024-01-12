package title_remover

import "core:fmt"
import "core:log"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:strings"
import "core:text/match"

import win "core:sys/windows"

print_usage :: proc() {
	fmt.println(
		`Usage:
$ title_remover.exe <Criterium> <Verb> <Arg>

Verbs:
	- exact    | x = exact match
	- regex    | r = regex match
	- contains | c = arg contained

Criterium:
	- title | t = window title
	- class | c = window class
	- file  | f = window executable file path

Example:
$ title_remover.exe title exact 'Minecraft Launcher'`,
	)
}

main :: proc() {
	ok := os.write_entire_file("log.txt", {0})
	log_file_handle, err := os.open("log.txt", mode = os.O_RDWR)
	if err != os.ERROR_NONE || !ok {
		fmt.eprintln("Failed to create loggger:", err)
		return
	}
	file_logger := log.create_file_logger(log_file_handle)
	
	defer{
		log.destroy_file_logger(&file_logger)
	}

	context.logger = file_logger
	
	handles := make([dynamic]win.HWND)
	win.EnumWindows(enum_windows_proc, transmute(win.LPARAM)&handles)

	if len(os.args) < 4 {
		log.error("Expected 3 Arguments, got", len(os.args) - 1)
		fmt.println("Expected 3 Arguments, got", len(os.args) - 1)
		print_usage()
		return
	}

	criterium: Criterium
	switch os.args[1] {
	case "title", "t":
		criterium = .Title
	case "class", "c":
		criterium = .Class
	case "file", "f":
		criterium = .File
	case:
		log.error("Unexpected criterium:", os.args[1])
		fmt.println("Unexpected criterium:", os.args[1])
		print_usage()
		return
	}

	match_mode: Match_Mode

	switch os.args[2] {
	case "x", "exact":
		match_mode = .Exact
	case "r", "regex":
		match_mode = .Regex
	case "c", "contains":
		match_mode = .Contain
	case:
		fmt.println("Unexpected verb:", os.args[2])
		log.error("Unexpected verb:", os.args[2])
		print_usage()
		return
	}

	arg := os.args[3]

	log.info("Criterium:", criterium)
	log.info("Match Mode:", match_mode)
	log.info("Arg:", arg)

	for handle in handles {
		criterium := get_criterium(handle, criterium) or_continue
		defer delete(criterium)

		if is_match(match_mode, criterium, arg) {
			log.info("Found matching window:", criterium)
			if remove_window_title_bar(handle) {
				log.info("Removed title bar from window")
			} else {
				log.error("Failed to remove title bar from window")
			}
		}

		free_all(context.temp_allocator)
	}
}

enum_windows_proc :: proc "stdcall" (hWnd: win.HWND, lParam: win.LPARAM) -> win.BOOL {
	context = runtime.default_context()

	handles := transmute(^[dynamic]win.HWND)lParam
	append(handles, hWnd)

	return true
}

Criterium :: enum {
	Title,
	Class,
	File,
}

get_criterium :: proc(handle: win.HWND, criterium: Criterium) -> (string, bool) {
	switch criterium {
	case .Title:
		return get_window_title(handle)
	case .Class:
		return get_window_class_name(handle)
	case .File:
		return get_window_module_file_name(handle)
	}

	return "", false
}

Match_Mode :: enum {
	Exact,
	Regex,
	Contain,
}

is_match :: proc(match_mode: Match_Mode, criterium, arg: string) -> bool {
	switch match_mode {
	case .Exact:
		return criterium == arg
	case .Contain:
		return strings.contains(criterium, arg)
	case .Regex:
		matcher := match.matcher_init(criterium, arg)
		_, n, matches := match.matcher_find(&matcher)
		if matches {
			return n == len(criterium)
		} else {
			return false
		}
	}
	unreachable()
}

remove_window_title_bar :: proc(hWnd: win.HWND) -> bool {
	if hWnd == nil {
		return false
	}

	preference: i32 = 2
	result := win.DwmSetWindowAttribute(
		hWnd,
		auto_cast win.DWMWINDOWATTRIBUTE.DWMWA_WINDOW_CORNER_PREFERENCE,
		&preference,
		size_of(preference),
	)

	return(
		win.SUCCEEDED(result) &&
		win.SetWindowLongW(hWnd, win.GWL_STYLE, transmute(i32)win.WS_POPUPWINDOW) != 0 \
	)
}

get_window_class_name :: proc(
	handle: win.HWND,
	allocator := context.allocator,
) -> (
	class_name: string,
	ok: bool,
) {
	MAX_CLASS_NAME :: 1024
	buffer := make([]u16, MAX_CLASS_NAME)
	defer delete(buffer)

	n := win.GetClassNameW(handle, raw_data(buffer), MAX_CLASS_NAME - 1)

	ok = n != 0 && n < MAX_CLASS_NAME

	class_name, _ = win.utf16_to_utf8(buffer[:n], allocator)

	return
}

get_window_module_file_name :: proc(
	handle: win.HWND,
	allocator := context.allocator,
) -> (
	file_name: string,
	ok: bool,
) {
	MAX_PATH :: 1024
	buffer := make([]u8, MAX_PATH, allocator)
	defer {
		if !ok {
			delete(buffer)
		}
	}

	dwProcId: u32 = 0

	win.GetWindowThreadProcessId(handle, &dwProcId)

	if dwProcId == 0 {
		return
	}

	hProc := win.OpenProcess(
		0x0400 | 0x0010, // win.PROCESS_QUERY_INFORMATION | win.PROCESS_VM_READ,
		false,
		dwProcId,
	)
	if hProc == nil {
		return
	}

	n := win.GetModuleFileNameExA(hProc, nil, raw_data(buffer), MAX_PATH)
	win.CloseHandle(hProc)

	if n == 0 || n == MAX_PATH {
		return
	} else {
		return string(buffer[:max(n, 100)]), true
	}

	return
}

get_window_title :: proc(
	handle: win.HWND,
	allocator := context.allocator,
) -> (
	title: string,
	ok: bool,
) {
	MAX_TITLE :: 1024
	buf := make([]u16, MAX_TITLE)
	defer delete(buf)

	n := win.GetWindowTextW(handle, raw_data(buf), MAX_TITLE - 1)

	ok = n != 0 && n != MAX_TITLE - 1
	if !ok do return

	title, _ = win.utf16_to_utf8(buf[:n], allocator)

	return
}
