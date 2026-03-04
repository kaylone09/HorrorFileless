# Fileless Clicker - Essential Edition
$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# P/Invoke per i click del mouse
$mouseHelper = @"
using System;
using System.Runtime.InteropServices;
public class MouseHelper {
    [DllImport("user32.dll")]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public MOUSEINPUT mi; }
    
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx, dy; public uint mouseData, dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }
    
    private const uint INPUT_MOUSE = 0;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008, MOUSEEVENTF_RIGHTUP = 0x0010;
    
    public static void ClickLeft() {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE; inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
        inputs[1].type = INPUT_MOUSE; inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
    public static void ClickRight() {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE; inputs[0].mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;
        inputs[1].type = INPUT_MOUSE; inputs[1].mi.dwFlags = MOUSEEVENTF_RIGHTUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@

$keyHelper = @"
using System;
using System.Runtime.InteropServices;
public class KeyHelper {
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
    public static bool IsPressed(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }
}
"@

Add-Type $mouseHelper
Add-Type $keyHelper

# Stato
$state = @{
    leftActive = $false; rightActive = $false
    leftCps = 10; rightCps = 10
    leftKey = 0; rightKey = 0
    waitingLeft = $false; waitingRight = $false
    skipL = $false; skipR = $false
    leftTimer = $null; rightTimer = $null; pollTimer = $null
    prevL = $false; prevR = $false
    drag = $false; dragPos = $null
}

# Mappa tasti
$keyMap = @{
    'F1'=0x70;'F2'=0x71;'F3'=0x72;'F4'=0x73;'F5'=0x74;'F6'=0x75;'F7'=0x76;'F8'=0x77;'F9'=0x78;'F10'=0x79;'F11'=0x7A;'F12'=0x7B
    'A'=0x41;'B'=0x42;'C'=0x43;'D'=0x44;'E'=0x45;'F'=0x46;'G'=0x47;'H'=0x48;'I'=0x49;'J'=0x4A;'K'=0x4B;'L'=0x4C
    'M'=0x4D;'N'=0x4E;'O'=0x4F;'P'=0x50;'Q'=0x51;'R'=0x52;'S'=0x53;'T'=0x54;'U'=0x55;'V'=0x56;'W'=0x57;'X'=0x58;'Y'=0x59;'Z'=0x5A
    'D0'=0x30;'D1'=0x31;'D2'=0x32;'D3'=0x33;'D4'=0x34;'D5'=0x35;'D6'=0x36;'D7'=0x37;'D8'=0x38;'D9'=0x39
    'Space'=0x20;'Shift'=0x10;'Control'=0x11;'Alt'=0x12
}

# GUI minimale
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Clicker'
$form.Size = New-Object System.Drawing.Size(400, 240)
$form.StartPosition = 'CenterScreen'
$form.BackColor = '#1C1C23'
$form.FormBorderStyle = 'None'
$form.TopMost = $true

# Barra titolo trascinabile
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Size = New-Object System.Drawing.Size(400, 30)
$titleBar.BackColor = '#26262D'
$titleBar.Add_MouseDown({
    if ($_.Button -eq 'Left') { $state.drag = $true; $state.dragPos = $_.Location }
})
$titleBar.Add_MouseMove({
    if ($state.drag) { $form.Location = New-Object Drawing.Point(($form.Location.X + $_.X - $state.dragPos.X), ($form.Location.Y + $_.Y - $state.dragPos.Y)) }
})
$titleBar.Add_MouseUp({ $state.drag = $false })
$form.Controls.Add($titleBar)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'CLICKER'
$title.Location = New-Object Drawing.Point(10, 5)
$title.Size = New-Object Drawing.Size(100, 20)
$title.ForeColor = '#B482FF'
$title.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$titleBar.Controls.Add($title)

$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = '×'
$closeBtn.Location = New-Object Drawing.Point(365, 0)
$closeBtn.Size = New-Object Drawing.Size(30, 30)
$closeBtn.FlatStyle = 'Flat'
$closeBtn.FlatAppearance.BorderSize = 0
$closeBtn.ForeColor = 'White'
$closeBtn.Font = New-Object Drawing.Font('Segoe UI', 14)
$closeBtn.Add_MouseEnter({ $_.BackColor = '#C83232' })
$closeBtn.Add_MouseLeave({ $_.BackColor = 'Transparent' })
$closeBtn.Add_Click({
    if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
    if ($state.pollTimer) { $state.pollTimer.Stop(); $state.pollTimer.Dispose() }
    $form.Close()
})
$titleBar.Controls.Add($closeBtn)

# Pannello sinistro - LEFT
$leftX, $topY = 15, 40

$lblLeft = New-Object System.Windows.Forms.Label
$lblLeft.Text = 'LEFT'
$lblLeft.Location = New-Object Drawing.Point($leftX, $topY)
$lblLeft.Size = New-Object Drawing.Size(150, 20)
$lblLeft.ForeColor = 'White'
$lblLeft.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$form.Controls.Add($lblLeft)

$btnLeftKey = New-Object System.Windows.Forms.Button
$btnLeftKey.Text = 'none'
$btnLeftKey.Location = New-Object Drawing.Point($leftX, $topY+20)
$btnLeftKey.Size = New-Object Drawing.Size(70, 25)
$btnLeftKey.FlatStyle = 'Flat'
$btnLeftKey.BackColor = '#3A3A44'
$btnLeftKey.ForeColor = 'White'
$btnLeftKey.Add_Click({
    $state.waitingLeft = $true
    $btnLeftKey.Text = '...'
    $btnLeftKey.BackColor = '#645078'
    $form.Focus()
})
$form.Controls.Add($btnLeftKey)

$lblLeftCps = New-Object System.Windows.Forms.Label
$lblLeftCps.Text = "$($state.leftCps) CPS"
$lblLeftCps.Location = New-Object Drawing.Point($leftX+80, $topY+20)
$lblLeftCps.Size = New-Object Drawing.Size(70, 25)
$lblLeftCps.ForeColor = '#B482FF'
$lblLeftCps.TextAlign = 'MiddleRight'
$form.Controls.Add($lblLeftCps)

$trackLeft = New-Object System.Windows.Forms.TrackBar
$trackLeft.Location = New-Object Drawing.Point($leftX, $topY+50)
$trackLeft.Size = New-Object Drawing.Size(160, 30)
$trackLeft.Minimum = 1
$trackLeft.Maximum = 100
$trackLeft.Value = $state.leftCps
$trackLeft.TickFrequency = 20
$trackLeft.BackColor = '#1C1C23'
$trackLeft.ForeColor = '#B482FF'
$trackLeft.Add_ValueChanged({
    $state.leftCps = $trackLeft.Value
    $lblLeftCps.Text = "$($state.leftCps) CPS"
    if ($state.leftActive) {
        $state.leftTimer.Stop()
        $state.leftTimer.Interval = [math]::Max(1, [int](1000/$state.leftCps))
        $state.leftTimer.Start()
    }
})
$form.Controls.Add($trackLeft)

# Pannello destro - RIGHT
$rightX = 205

$lblRight = New-Object System.Windows.Forms.Label
$lblRight.Text = 'RIGHT'
$lblRight.Location = New-Object Drawing.Point($rightX, $topY)
$lblRight.Size = New-Object Drawing.Size(150, 20)
$lblRight.ForeColor = 'White'
$lblRight.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$form.Controls.Add($lblRight)

$btnRightKey = New-Object System.Windows.Forms.Button
$btnRightKey.Text = 'none'
$btnRightKey.Location = New-Object Drawing.Point($rightX, $topY+20)
$btnRightKey.Size = New-Object Drawing.Size(70, 25)
$btnRightKey.FlatStyle = 'Flat'
$btnRightKey.BackColor = '#3A3A44'
$btnRightKey.ForeColor = 'White'
$btnRightKey.Add_Click({
    $state.waitingRight = $true
    $btnRightKey.Text = '...'
    $btnRightKey.BackColor = '#645078'
    $form.Focus()
})
$form.Controls.Add($btnRightKey)

$lblRightCps = New-Object System.Windows.Forms.Label
$lblRightCps.Text = "$($state.rightCps) CPS"
$lblRightCps.Location = New-Object Drawing.Point($rightX+80, $topY+20)
$lblRightCps.Size = New-Object Drawing.Size(70, 25)
$lblRightCps.ForeColor = '#B482FF'
$lblRightCps.TextAlign = 'MiddleRight'
$form.Controls.Add($lblRightCps)

$trackRight = New-Object System.Windows.Forms.TrackBar
$trackRight.Location = New-Object Drawing.Point($rightX, $topY+50)
$trackRight.Size = New-Object Drawing.Size(160, 30)
$trackRight.Minimum = 1
$trackRight.Maximum = 100
$trackRight.Value = $state.rightCps
$trackRight.TickFrequency = 20
$trackRight.BackColor = '#1C1C23'
$trackRight.ForeColor = '#B482FF'
$trackRight.Add_ValueChanged({
    $state.rightCps = $trackRight.Value
    $lblRightCps.Text = "$($state.rightCps) CPS"
    if ($state.rightActive) {
        $state.rightTimer.Stop()
        $state.rightTimer.Interval = [math]::Max(1, [int](1000/$state.rightCps))
        $state.rightTimer.Start()
    }
})
$form.Controls.Add($trackRight)

# Hotkey indicator
$hotkeyLabel = New-Object System.Windows.Forms.Label
$hotkeyLabel.Text = 'F6 (L) | F7 (R) | F8 (STOP)'
$hotkeyLabel.Location = New-Object Drawing.Point(15, 190)
$hotkeyLabel.Size = New-Object Drawing.Size(370, 20)
$hotkeyLabel.ForeColor = '#8C8CA0'
$hotkeyLabel.TextAlign = 'MiddleCenter'
$hotkeyLabel.Font = New-Object Drawing.Font('Segoe UI', 8)
$form.Controls.Add($hotkeyLabel)

# Funzioni
function Toggle-Left {
    $state.leftActive = -not $state.leftActive
    if ($state.leftActive) {
        $btnLeftKey.BackColor = '#8C64C8'
        if ($state.leftTimer) { $state.leftTimer.Dispose() }
        $state.leftTimer = New-Object System.Windows.Forms.Timer
        $state.leftTimer.Interval = [math]::Max(1, [int](1000/$state.leftCps))
        $state.leftTimer.Add_Tick({ [MouseHelper]::ClickLeft() })
        $state.leftTimer.Start()
    } else {
        $btnLeftKey.BackColor = '#3A3A44'
        if ($state.leftTimer) { $state.leftTimer.Stop() }
    }
}

function Toggle-Right {
    $state.rightActive = -not $state.rightActive
    if ($state.rightActive) {
        $btnRightKey.BackColor = '#8C64C8'
        if ($state.rightTimer) { $state.rightTimer.Dispose() }
        $state.rightTimer = New-Object System.Windows.Forms.Timer
        $state.rightTimer.Interval = [math]::Max(1, [int](1000/$state.rightCps))
        $state.rightTimer.Add_Tick({ [MouseHelper]::ClickRight() })
        $state.rightTimer.Start()
    } else {
        $btnRightKey.BackColor = '#3A3A44'
        if ($state.rightTimer) { $state.rightTimer.Stop() }
    }
}

# Key binding
$form.Add_KeyDown({
    $key = $_.KeyCode.ToString()
    if ($state.waitingLeft -and $keyMap.ContainsKey($key)) {
        $state.leftKey = $keyMap[$key]
        $btnLeftKey.Text = $key
        $btnLeftKey.BackColor = '#3A3A44'
        $state.waitingLeft = $false
        $state.skipL = $true
    }
    elseif ($state.waitingRight -and $keyMap.ContainsKey($key)) {
        $state.rightKey = $keyMap[$key]
        $btnRightKey.Text = $key
        $btnRightKey.BackColor = '#3A3A44'
        $state.waitingRight = $false
        $state.skipR = $true
    }
    elseif ($_.KeyCode -eq 'F6' -and $state.leftKey -ne 0) { Toggle-Left }
    elseif ($_.KeyCode -eq 'F7' -and $state.rightKey -ne 0) { Toggle-Right }
    elseif ($_.KeyCode -eq 'F8') {
        if ($state.leftActive) { Toggle-Left }
        if ($state.rightActive) { Toggle-Right }
    }
})

# Polling tasti
$state.pollTimer = New-Object System.Windows.Forms.Timer
$state.pollTimer.Interval = 50
$state.pollTimer.Add_Tick({
    if ($state.leftKey -ne 0) {
        $pressed = [KeyHelper]::IsPressed($state.leftKey)
        if ($pressed -and -not $state.prevL) {
            if (-not $state.skipL) { Toggle-Left } else { $state.skipL = $false }
            $state.prevL = $true
        } elseif (-not $pressed) { $state.prevL = $false }
    }
    if ($state.rightKey -ne 0) {
        $pressed = [KeyHelper]::IsPressed($state.rightKey)
        if ($pressed -and -not $state.prevR) {
            if (-not $state.skipR) { Toggle-Right } else { $state.skipR = $false }
            $state.prevR = $true
        } elseif (-not $pressed) { $state.prevR = $false }
    }
})
$state.pollTimer.Start()

$form.Add_FormClosing({
    if ($state.leftTimer) { $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Dispose() }
    if ($state.pollTimer) { $state.pollTimer.Dispose() }
})

[void]$form.ShowDialog()
