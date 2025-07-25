#Requires AutoHotkey v2.0
#Include ./lib/OCR.ahk
#Include ./lib/FuzzyMatch.ahk
#SingleInstance Force

Fuz := Fuzzy()

settingsFile := "settings.ini"

DEBUG_egg_buy := true
DEBUG_seed_buy := true
DEBUG_gear_buy := true
DEBUG_skip_failsafes := false
DEBUG_skip_macro_align := false
DEBUG_direct_run := false

; DEBUG_egg_buy := true
; DEBUG_seed_buy := false
; DEBUG_gear_buy := false
; DEBUG_skip_failsafes := true
; DEBUG_skip_macro_align := true
; DEBUG_direct_run := true

; Read and parse JSON
if !FileExist(settingsFile) {
    MsgBox("settings.ini file not found.")
    ExitApp
}

macro_running := false
last_fired_egg := 0
last_fired_shop := 0
loop_counter := 0
trigger_egg_macro := false
show_timestamp_tooltip := false
mouse_x := 0
mouse_y := 0
first_run := true

window := Gui("+Resize", "Rus' Grow a Garden Macro")
window.SetFont("s10")

ReadEntireIni(filePath) {
    result := Map()
    sections := StrSplit(IniRead(filePath), "`n")

    for i, section in sections {
        iniSection := StrSplit(IniRead(filePath, section), "`n")

        result[section] := Map()

        for j, line in iniSection {
            if (line != "") {
                key := StrSplit(line, "=")[1]
                value := StrSplit(line, "=")[2]

                if(section = "Settings"){
                    if(RegExMatch(value, "^-?\d+$")){
                        value := value + 0
                    }
                }

                result[section][key] := value
            }
        }
    }

    return result
}

SetSetting(section, key, value) {
    global settingsFile
    IniWrite(value, settingsFile, section, key)
}
CONFIG := ReadEntireIni(settingsFile)

; Positions and sizes for 3 columns
x1 := 10, y1 := 0, w := 250
x2 := x1 + w + 20
x3 := x2 + w + 20

seedList := [
    "Carrot", "Strawberry", "Blueberry", "Orange Tulip", "Tomato", "Corn", "Daffodil",
    "Watermelon", "Pumpkin", "Apple", "Bamboo", "Coconut", "Cactus",
    "Dragon Fruit", "Mango", "Grape", "Mushroom", "Pepper", "Cacao",
    "Beanstalk", "Ember Lily", "Sugar Apple", "Burning Bud", "Giant Pinecone"
]

gearList := [
    "Watering Can", "Trowel", "Recall Wrench", "Basic Sprinkler", "Advanced Sprinkler",
    "Medium Toy", "Medium Treat", "Godly Sprinkler", "Magnifying Glass", "Tanning Mirror", 
    "Master Sprinkler", "Cleaning Spray", "Favorite Tool", "Harvest Tool", "Friendship Pot",
    "Levelup Lolipop"
]

eggList := [
    "Common Egg", "Common Summer Egg", "Rare Summer Egg", "Mythical Egg",
    "Paradise Egg", "Bug Egg"
]

JoinArr(arr, delim := ",") {
    result := ""
    for i, item in arr {
        if (i > 1) {
            result .= delim
        }
        result .= item
    }
    return result
}

Array.Prototype.DefineProp("Join", { Call: JoinArr })

seedIndexes := []
gearIndexes := []
eggIndexes := []

GetOCR() {
    global OCR
    return OCR.FromDesktop().Text
}

GetOCRRect(x, y, w, h, opts := {}) {
    global OCR
    return OCR.FromRect(x, y, w, h, opts).Text
}

JoinMap(m, delim := "`n") {
    str := ""
    for key, val in m {
        if IsObject(val) ; Check if val is a Map (or Object with keys)
            serializedVal := "{" . JoinMap(val, ",") . "}"
        else
            serializedVal := val
        str .= key "=" serializedVal delim
    }
    return RTrim(str, delim)  ; remove trailing delimiter
}

; Create GroupBoxes
; Now populate each column — example for eggs:
seedCheckboxes := AddItemsToColumn(window, "Seeds", seedList, x1 + 10, y1 + 20)
gearCheckboxes := AddItemsToColumn(window, "Gears", gearList, x2 + 10, y1 + 20)
eggCheckboxes := AddItemsToColumn(window, "Eggs", eggList, x3 + 10, y1 + 20)

AddItemsToColumn(gui, label, items, x, startY) {
    global CONFIG
    y := startY
    i := 0
    
    labelVar := window.addText(" x" x " y" y " h40 w200", label)
    labelVar.SetFont("s16 Bold")
    y += 30

    checkboxes := []

    for key, value in items {
        chk := window.Add("Checkbox", "x" x " y" y " w200", value)

        value := CONFIG[label][value]
        chk.Value := value = "true"

        i++
        y += 25

        checkboxes.Push(chk)
    }

    return checkboxes
}

DebugLog(text, newLine := 0){
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    if(newLine) {
        FileAppend("`n", "debug_log.txt")
    }

    if Type(text) == "Integer" {
        text := "(Integer) " text
    } else if Type(text) == "Float" {
        text := "(Float) " text
    } else if Type(text) == "String" {
        text := "(String) " text
    } else if Type(text) == "Object" {
        text := "(Map) " JoinMap(text)
    } else if Type(text) == "Array" {
        text := "[" JoinArr(text) "]"
    }
    FileAppend("`n[" timestamp "] "  text, "debug_log.txt")
}

HoldKey(key, sec) {
    Send("{" key " down}")
    Sleep(sec * 1000)
    Send("{" key " up}")
}

ManyPress(string, delay := 200){
    ; split the string by spaces
    parts := StrSplit(string, " ")
    for part in parts {
        if(macro_running = false) {
            break
        }
        Press(part, 1, delay)
    }
}

GetDiffs(arr) {
    diffs := []
    for i, val in arr {
        if (i = 1)
            diffs.Push(val) ; or push 0, or skip it depending on your preference
        else
            diffs.Push(val - arr[i - 1])
    }
    return diffs
}

Press(key, num := 1, delay := 100) {
    activeWindow := WinGetTitle("A")
    if(CONFIG['Settings']["window_failsafe"] = "true" && activeWindow != "Roblox" && activeWindow != "Rus' Grow a Garden Macro") {
        SetToolTip("")
        MsgBox("Roblox window must be focused as a failsafe.`nMacro has been terminated.`n" ToT())
        ExitApp
        return
    } else loop num {
        if(macro_running == false) {
            break
        }
        ; get the current focused window
        Sleep(delay)
        Send("{" key "}")
        if(macro_running == false) {
            break
        }
    }
}

SetToolTip(text) {
    global CONFIG
    if(!macro_running) {
        ToolTip("")  ; Clear tooltip if macro is not running
        return
    } else if(CONFIG['Settings']["show_tooltips"] = "true") {
        ToolTip(text)
    }
}

LeftClick(){
    Click("left")
}

SmoothMove(toX, toY, steps := 10, delay := 2) {
    MouseGetPos(&x, &y)
    dx := (toX - x) / steps
    dy := (toY - y) / steps

    Loop steps {
        if(macro_running = false) {
            break
        }
        x += dx
        y += dy
        MouseMove(x, y, 0)  ; instant per step, but appears smooth
        Sleep(delay)
    }
}

StartMacro(*) {
    global macro_running, seedIndexes, gearIndexes, eggIndexes, CONFIG, DEBUG_direct_run, trigger_egg_macro
    if !macro_running {

        ; get all properties from CONFIG["Config"][/(.)_set$/]

        setProperties := []
        for prop in CONFIG["Config"]
            setProperties.Push(prop)

        for prop in setProperties {
            if(RegExMatch(prop, "(.+)_set$") && CONFIG["Config"][prop] = "false") {
                MsgBox("required config setting `"" StrReplace(prop, "_set", "") "`" not set!`nHit the 'Set Config' button to do so.")
                Kill()
                return
            }
        }

        SetToolTip("Getting data from settings.ini")
        for i, chk in seedCheckboxes {
            SetSetting("Seeds", chk.Text, chk.Value == 1 ? "true" : "false")
            if(chk.Value == 1) {
                seedIndexes.Push(i)
            }
        }

        for i, chk in gearCheckboxes {
            SetSetting("Gears", chk.Text, chk.Value == 1 ? "true" : "false")
            if(chk.Value == 1) {
                gearIndexes.Push(i)
            }
        }

        for i, chk in eggCheckboxes {
            SetSetting("Eggs", chk.Text, chk.Value == 1 ? "true" : "false")
            if(chk.Value == 1) {
                eggIndexes.Push(i)
            }
        }

        macro_running := true
        SetToolTip("Starting macro...")
        Sleep(CONFIG['Settings']["grace"] * 1000)
        SetToolTip("")
        WinMinimize("Rus' Grow a Garden Macro")
        WinActivate("Roblox")

        Sleep(300)

        if(DEBUG_direct_run){
            trigger_egg_macro := true
            Macro()
        } else {
            SetTimer(Master, 100)
        }
    }
}

AlignCamera() {
    global first_run
    ; turn on shift lock + follow camera
    ManyPress("Esc Tab D S D D Esc")
    Sleep(1000)

    ; reset camera orbit by looking down with shiftlock on
    SetToolTip("Reset camera orbit")
    Press("LShift")
    Sleep(500)
    SmoothMove(A_ScreenWidth / 2, A_ScreenHeight)
    SetToolTip("")

    ; turn off shift lock
    ManyPress("Esc Tab D Esc")
    Sleep(500)

    ; align camera
    SetToolTip("Aligning camera")
    loop 8 {
        if(macro_running = false) {
            break
        }
        ClickScreen("seeds")
        ClickScreen("sell")
    }
    ClickScreen("seeds")
    SetToolTip("")

    ; turn off follow camera
    ManyPress("Esc Tab S D D Esc")

    ; reset zoom
    if(first_run == true){
        Sleep(800)
        SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
        Sleep(800)
        ClickScreen("garden")
        Sleep(2000)
        SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
        Sleep(1000)
        LeftClick()
        SetToolTip("Resetting zoom")
        Loop 100 {
            if(macro_running = false) {
                break
            }
            Send("{WheelUp}")
        }
        Sleep(500)
        LeftClick()
        LeftClick()
        Loop 8 {
            if(macro_running = false) {
                break
            }
            Send("{WheelDown}")
            Sleep(250)
        }
    }
    SetToolTip("")
}

/**
 * 
 * @param name - "gear", "gear exit", "seeds", "seed exit", "egg enter", "egg exit", "sell", "garden"
 */
ClickScreen(name){
    ; gear, gear exit, seed, seed exit, egg, sell, garden
    c := CONFIG['Config']

    if(name == "gear"){
        SmoothMove(c["gear_enter_point_x"],c["gear_enter_point_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "gear exit") {
        SmoothMove(c["gear_shop_exit_button_x"], c["gear_shop_exit_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "seeds") {
        SmoothMove(c["seed_shop_button_x"], c["seed_shop_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "seed exit") {
        SmoothMove(c["seed_shop_exit_button_x"], c["seed_shop_exit_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "egg enter") {
        SmoothMove(c["egg_enter_point_x"], c["egg_enter_point_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "egg exit") {
        SmoothMove(c["egg_shop_exit_button_x"], c["egg_shop_exit_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "sell") {
        SmoothMove(c["sell_button_x"], c["sell_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    } else if(name == "garden") {
        SmoothMove(c["garden_button_x"], c["garden_button_y"],, 0.5)
        Sleep(100)
        LeftClick()
    }
}

setConfig(*) {
    global CONFIG, macro_running, mouse_x, mouse_y
    if !macro_running {
        macro_running := true
        SetToolTip("Starting config set...")
        Sleep(CONFIG['Settings']["grace"] * 1000)
        SetToolTip("")
        WinMinimize("Rus' Grow a Garden Macro")
        WinActivate("Roblox")

        waitForMouseClick("Click on the `"Seeds`" button at the top of the screen (seed_shop_button)")
        setConfigAndIniValue("seed_shop_button", mouse_x, mouse_y)
        Sleep(2000)
        Press("E")
        Sleep(2200)

        waitForMouseClick("Click on the `"X`" button at the top right of the seed shop (seed_shop_exit_button)")
        setConfigAndIniValue("seed_shop_exit_button", mouse_x, mouse_y)
        Sleep(1000)

        waitForMouseClick("Click on the `"Garden`" button at the top of the screen (garden_button)")
        setConfigAndIniValue("garden_button", mouse_x, mouse_y)
        Sleep(1000)

        waitForMouseClick("Click on the `"Sell`" button at the top of the screen (sell_button)")
        setConfigAndIniValue("sell_button", mouse_x, mouse_y)
        Sleep(1000)

        first_run := true
        AlignCamera()

        Sleep(1000)
        Press("2")
        Sleep(100)
        LeftClick()
        Sleep(500)
        Press("E")
        Sleep(2000)

        waitForMouseClick("Click the dialogue option to enter the gear shop (gear_enter_point)")
        setConfigAndIniValue("gear_enter_point", mouse_x, mouse_y)
        Sleep(2200)

        waitForMouseClick("Click on the `"X`" button at the top right of the gear shop (gear_shop_exit_button)")
        setConfigAndIniValue("gear_shop_exit_button", mouse_x, mouse_y)
        Sleep(1000)

        HoldKey("S", 0.67)
        Press("E")
        Sleep(2200)
        waitForMouseClick("Click the dialogue option to enter the egg shop (egg_enter_point)")
        setConfigAndIniValue("egg_enter_point", mouse_x, mouse_y)
        Sleep(1000)

        Press("E")
        Sleep(2000)
        WaitForMouseClick("Click on the `"X`" button at the top right of the egg shop (egg_exit_button)")
        setConfigAndIniValue("egg_shop_exit_button", mouse_x, mouse_y)
        Sleep(1000)


        ToolTip("Done! You can now run the macro.")
        macro_running := false
        
        SetTimer((*) => (
            ToolTip("")
        ), 2000)
    }
}

waitForMouseClick(msg){
    global mouse_x, mouse_y
    t() {
        if(macro_running = false) {
            ToolTip("")
            Kill()
            return
        }
        ToolTip(msg)
    }
    SetTimer(t, 16)
    KeyWait("LButton", "D")
    MouseGetPos(&mouse_x, &mouse_y)
    ToolTip("")
    SetTimer(t, 0)
}

setConfigAndIniValue(name, x, y){
    SetSetting("Config", name "_set", "true")
    SetSetting("Config", name "_x", x)
    SetSetting("Config", name "_y", y)

    CONFIG['Config'][name "_set"] := "true"
    CONFIG['Config'][name "_x"] := x
    CONFIG['Config'][name "_y"] := y
}

startButton := window.AddButton("x" x1 " y650 w100", "Start")
configButton := window.AddButton("x" (x1 + 110) " y650 w130", "Set Config")

startButton.OnEvent("Click", StartMacro)
configButton.OnEvent("Click", setConfig)

window.Show("AutoSize Center")

Kill(*) {
    global macro_running
    if macro_running {
        macro_running := false
        SetTimer(Master, 0)
        SetToolTip("")
        
        MsgBox("Macro stopped.")
        ExitApp
    }
}

Hotkey(CONFIG['Settings']['kill_key'], Kill)

getUnixTimeStamp() {
    epoch := "19700101000000"
    local_diff := DateDiff(A_Now, epoch, "Seconds")
    utc_offset_seconds := DateDiff(A_Now, A_NowUTC, "Seconds")
    unix_timestamp := local_diff - utc_offset_seconds
    return unix_timestamp
}

Master() {
    global loop_counter, last_fired_egg, last_fired_shop, CONFIG, trigger_egg_macro, show_timestamp_tooltip, first_run

    shopInterval := CONFIG['Settings']["shop_timer"]
    eggInterval := CONFIG['Settings']["egg_timer"]

    ; macro logic here
    current_time := getUnixTimeStamp()
    nextShopCheckIn := shopInterval - Mod(getUnixTimeStamp(), shopInterval)
    nextEggCheckIn := eggInterval - Mod(getUnixTimeStamp(), eggInterval)

    if(show_timestamp_tooltip){
        SetToolTip("Next shop check in " nextShopCheckIn "s`nNext egg check in " nextEggCheckIn "s")
    } else {
        SetToolTip("")
    }


    if !macro_running {
        Kill()
        return
    }

    if(first_run || (Mod(getUnixTimeStamp(), eggInterval) = 0) && (current_time != last_fired_egg)){
        last_fired_egg := current_time
        trigger_egg_macro := true
    }

    if(first_run || (Mod(getUnixTimeStamp(), shopInterval) = 0) && (current_time != last_fired_shop)) {
        last_fired_shop := current_time
        Macro()
    }

    if(first_run) {
        first_run := false
    }
}

/**
 * Time of Termination
 */
ToT(){
    timestamp := FormatTime(, "dd/MM/yyyy HH:mm:ss")
    return "Time of termination: " . timestamp
}

Macro() {
    global CONFIG, trigger_egg_macro, seedIndexes, gearIndexes, eggIndexes, show_timestamp_tooltip, seedList, gearList, first_run

    global DEBUG_egg_buy, DEBUG_seed_buy, DEBUG_gear_buy, DEBUG_skip_failsafes, DEBUG_skip_macro_align, macro_running

    show_timestamp_tooltip := false

    ; IOAGTEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
    ; if(first_run){
    ;     ClickScreen("seed exit")
    ; }

    if(DEBUG_skip_macro_align == false){
        AlignCamera()
    }

    if(DEBUG_skip_failsafes == false){
        scanCount := CONFIG["Settings"]["failsafe_scan_count"]

        internetFailsafeCount := 0
        shutdownFailsafeCount := 0
        otherFailsafeCount := 0

        SetToolTip("Checking failsafes...")
        Sleep(1000)
        SmoothMove(A_ScreenWidth, A_ScreenHeight)
        Sleep(800)
        SetToolTip("")
        i := 1
        Loop scanCount {
            if(macro_running = false) {
                break
            }

            ocr := GetOCR()

            if(CONFIG["Settings"]["internet_failsafe"] == "true"){
                if(ocr == "Disconnected Lost connection to the game server, please reconnect (Error Code: 277) Leave Reconnect") {
                    internetFailsafeCount++
                }
            }

            if(CONFIG["Settings"]["shutdown_failsafe"] == "true"){
                if(ocr == "Disconnected The game has shut down (Error Code: 288) Leave Reconnect") {
                    shutdownFailsafeCount++
                }
            }

            if(CONFIG["Settings"]["other_failsafe"] == "true"){
                if(RegExMatch(ocr, "Disconnected (.*) Leave Reconnect")) {
                    otherFailsafeCount++
                }
            }

            i++
        }

        if(internetFailsafeCount > (scanCount / 2)){
            MsgBox("Internet was disconnected`nMacro has been terminated.`n" ToT())
            ExitApp
            return
        }

        if(shutdownFailsafeCount > (scanCount / 2)){
            MsgBox("Server has shut down`nMacro has been terminated.`n" ToT())
            ExitApp
            return
        }

        if(otherFailsafeCount > (scanCount / 2)){
            MsgBox("Game was terminated for an unspecified reason`nMacro has been terminated.`n" ToT())
            ExitApp
            return
        }

        SetToolTip("")
    }

    Sleep(1000)

    ; enter seed shop
    if(DEBUG_seed_buy){
        ClickScreen("seeds")
        Sleep(1000)
        Press("E")
        Sleep(2500)

        SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
        Loop 100 {
            if(macro_running = false) {
                break
            }
            Send("{WheelDown}")
        }
        Sleep(1000)
        Press("\")

        ; buy seeds
        seedDiffs := GetDiffs(seedIndexes)
        seedDiffs[1] -= 1
        ; loop through seedIndexes to buy the right seeds
        for i, seedIndex in seedDiffs {
            if(macro_running = false) {
                break
            }
            SetToolTip("Buying " seedList[seedIndexes[i]] " seed if in stock")
            Press("S", seedIndex)
            Press("Enter")
            Press("S")

            Press("Enter", 30, 50)
            
            Press("W")
            Press("Enter")
            SetToolTip("")
        }
        Press("\")
        Sleep(900)
        ClickScreen("seed exit")
    }

    if(DEBUG_gear_buy){
        Sleep(1000)

        ; go to gear shop
        Sleep(500)
        Press("2", 1)
        LeftClick()
        Sleep(500)
        Press("E", 1)

        ; enter gear shop
        Sleep(2000)
        ClickScreen("gear")
        Sleep(2000)
        SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
        Sleep(1000)
        Loop 100 {
            if(macro_running = false) {
                break
            }
            Send("{WheelDown}")
        }
        Sleep(1000)
        Press("\")

        ; buy gears
        gearDiffs := GetDiffs(gearIndexes)
        gearDiffs[1] -= 1

        for i, gearIndex in gearDiffs {
            if(macro_running = false) {
                break
            }

            SetToolTip("Buying " gearList[gearIndexes[i]] " gear if in stock")
            Press("S", gearIndex)
            Press("Enter")
            Press("S")

            Press("Enter", 6, 50)
            
            Press("W")
            Press("Enter")
            SetToolTip("")
        }
        Press("\")
        Sleep(900)
        ClickScreen("gear exit")
    }

    if(trigger_egg_macro && DEBUG_egg_buy) {
        Sleep(100)
        HoldKey("S", 0.67)
        Sleep(500)
        Press("E")
        Sleep(2200)
        ClickScreen("egg enter")
        Sleep(2000)
        SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)
        Sleep(1000)
        Loop 100 {
            if(macro_running = false) {
                break
            }
            Send("{WheelDown}")
        }
        Sleep(1000)
        Press("\")

        ; get diffs
        eggDiffs := GetDiffs(eggIndexes)
        eggDiffs[1] -= 1


        for i, eggIndex in eggDiffs {
            if(macro_running = false) {
                break
            }
            SetToolTip("Buying " eggList[eggIndexes[i]] " gear if in stock")
            Press("S", eggDiffs[i] * 2)
            Sleep(200)
            Press("Enter")
            Sleep(200)
            Press("S", 2)
            Sleep(200)
            Press("Enter", 3, 50)
            Sleep(200)
            Press("W")
            Sleep(200)
            Press("Enter")
            Sleep(200)
            SetToolTip("")
            Sleep(1000)
        }

        Press("\")
        Sleep(900)
        ClickScreen("egg exit")


        trigger_egg_macro := false
    }

    Sleep(1000)
    ClickScreen("garden")
    SmoothMove(A_ScreenWidth / 2, A_ScreenHeight / 2)

    show_timestamp_tooltip := true
}