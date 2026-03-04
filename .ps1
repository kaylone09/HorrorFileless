# Horror Fileless - by Horror (Versione Unica)

$ErrorActionPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- P/Invoke for SendInput and GetAsyncKeyState ---
$script:uid1 = -join ((65..90) + (97..122) | Get-Random -Count 15 | % { [char]$_ })
$script:uid2 = -join ((65..90) + (97..122) | Get-Random -Count 14 | % { [char]$_ })

$nativeCode = @"
using System;
using System.Runtime.InteropServices;

public class $($script:uid1) {
    [DllImport("user32.dll", CharSet = CharSet.Auto, CallingConvention = CallingConvention.StdCall)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx; public int dy;
        public uint mouseData; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }

    private const uint INPUT_MOUSE          = 0;
    private const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP   = 0x0010;

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

public class $($script:uid2) {
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
    public static bool IsPressed(int vKey) { return (GetAsyncKeyState(vKey) & 0x8000) != 0; }
}
"@

if (-not ([System.Management.Automation.PSTypeName]$script:uid1).Type) {
    Add-Type -TypeDefinition $nativeCode
}

# --- Global state ---
$state = @{
    leftActive     = $false
    rightActive    = $false
    leftCps        = 10
    rightCps       = 10
    leftVK         = 0
    rightVK        = 0
    waitingLeft    = $false
    waitingRight   = $false
    skipToggleL    = $false
    skipToggleR    = $false
    leftTimer      = $null
    rightTimer     = $null
    pollTimer      = $null
    leftBarDrag    = $false
    rightBarDrag   = $false
    formDrag       = $false
    formDragOrigin = $null
    prevKeyL       = $false
    prevKeyR       = $false
    bgImage        = $null
}

# Supported keys map (VK codes)
$keyMap = @{
    'F1'=0x70;'F2'=0x71;'F3'=0x72;'F4'=0x73;'F5'=0x74;'F6'=0x75
    'F7'=0x76;'F8'=0x77;'F9'=0x78;'F10'=0x79;'F11'=0x7A;'F12'=0x7B
    'A'=0x41;'B'=0x42;'C'=0x43;'D'=0x44;'E'=0x45;'F'=0x46
    'G'=0x47;'H'=0x48;'I'=0x49;'J'=0x4A;'K'=0x4B;'L'=0x4C
    'M'=0x4D;'N'=0x4E;'O'=0x4F;'P'=0x50;'Q'=0x51;'R'=0x52
    'S'=0x53;'T'=0x54;'U'=0x55;'V'=0x56;'W'=0x57;'X'=0x58
    'Y'=0x59;'Z'=0x5A
    'D0'=0x30;'D1'=0x31;'D2'=0x32;'D3'=0x33;'D4'=0x34
    'D5'=0x35;'D6'=0x36;'D7'=0x37;'D8'=0x38;'D9'=0x39
    'Space'=0x20;'Shift'=0x10;'Control'=0x11;'Alt'=0x12
    'XButton1'=0x05;'XButton2'=0x06
}

# --- Download immagine (NUOVO LINK) ---
$tmpId = Get-Random -Minimum 1000 -Maximum 9999
$imgPath = "$env:TEMP\$tmpId.tmp"

if (-not (Test-Path $imgPath)) {
    try {
        $wr = [System.Net.WebRequest]::Create('https://raw.githubusercontent.com/kaylone09/test/refs/heads/main/test.jpg')
        $wr.Timeout = 5000
        $resp = $wr.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($imgPath)
        $stream.CopyTo($fs)
        $fs.Close(); $stream.Close(); $resp.Close()
    } catch {}
}

if (Test-Path $imgPath) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($imgPath)
        $ms = New-Object System.IO.MemoryStream(@(,$bytes))
        $state.bgImage = [System.Drawing.Image]::FromStream($ms)
    } catch {}
}

# ============================================================
# GUI con Tema Horror Fileless - SENZA BORDI
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Horror Fileless'
$form.Size            = New-Object System.Drawing.Size(600, 400)
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = [System.Drawing.Color]::FromArgb(28, 28, 35)
$form.FormBorderStyle = 'None'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $true
$form.KeyPreview      = $true
$form.TopMost         = $true

# --- Titlebar ---
$header = New-Object System.Windows.Forms.Panel
$header.Location  = New-Object System.Drawing.Point(0, 0)
$header.Size      = New-Object System.Drawing.Size(600, 70)
$header.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 45)
$form.Controls.Add($header)

$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Text      = '—'
$btnMin.Location  = New-Object System.Drawing.Point(520, 20)
$btnMin.Size      = New-Object System.Drawing.Size(30, 30)
$btnMin.FlatStyle = 'Flat'
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.BackColor = [System.Drawing.Color]::Transparent
$btnMin.ForeColor = [System.Drawing.Color]::White
$btnMin.Font      = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$btnMin.Add_MouseEnter({ $btnMin.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 80) })
$btnMin.Add_MouseLeave({ $btnMin.BackColor = [System.Drawing.Color]::Transparent })
$btnMin.Add_Click({ $form.WindowState = 'Minimized' })
$header.Controls.Add($btnMin)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text      = '×'
$btnClose.Location  = New-Object System.Drawing.Point(555, 20)
$btnClose.Size      = New-Object System.Drawing.Size(30, 30)
$btnClose.FlatStyle = 'Flat'
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$btnClose.Add_MouseEnter({ $btnClose.BackColor = [System.Drawing.Color]::FromArgb(200, 50, 50) })
$btnClose.Add_MouseLeave({ $btnClose.BackColor = [System.Drawing.Color]::Transparent })
$btnClose.Add_Click({
    if ($state.leftTimer)  { $state.leftTimer.Stop();  $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
    if ($state.pollTimer)  { $state.pollTimer.Stop();  $state.pollTimer.Dispose() }
    $form.Close()
})
$header.Controls.Add($btnClose)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'Horror Fileless'
$lblTitle.Location  = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size      = New-Object System.Drawing.Size(300, 40)
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$lblTitle.TextAlign = 'MiddleLeft'
$header.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text      = 'by Daanii06_'
$lblSubtitle.Location  = New-Object System.Drawing.Point(20, 50)
$lblSubtitle.Size      = New-Object System.Drawing.Size(200, 20)
$lblSubtitle.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Italic)
$lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 160)
$lblSubtitle.TextAlign = 'MiddleLeft'
$header.Controls.Add($lblSubtitle)

# --- Pannello sinistro ---
$leftPanel = New-Object System.Windows.Forms.Panel
$leftPanel.Location  = New-Object System.Drawing.Point(20, 90)
$leftPanel.Size      = New-Object System.Drawing.Size(300, 250)
$leftPanel.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 45)
$leftPanel.BorderStyle = 'None'
$form.Controls.Add($leftPanel)

$lblLeftTitle = New-Object System.Windows.Forms.Label
$lblLeftTitle.Text      = 'LEFT CLICK'
$lblLeftTitle.Location  = New-Object System.Drawing.Point(15, 15)
$lblLeftTitle.Size      = New-Object System.Drawing.Size(270, 25)
$lblLeftTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblLeftTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblLeftTitle.TextAlign = 'MiddleLeft'
$leftPanel.Controls.Add($lblLeftTitle)

$btnLeftKey = New-Object System.Windows.Forms.Button
$btnLeftKey.Text      = 'none'
$btnLeftKey.Location  = New-Object System.Drawing.Point(15, 50)
$btnLeftKey.Size      = New-Object System.Drawing.Size(100, 35)
$btnLeftKey.FlatStyle = 'Flat'
$btnLeftKey.FlatAppearance.BorderSize = 0
$btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
$btnLeftKey.ForeColor = [System.Drawing.Color]::White
$btnLeftKey.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnLeftKey.Add_Click({
    $state.waitingLeft = $true
    $btnLeftKey.Text      = '...'
    $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(100, 80, 120)
    $lblStatus.Text = 'suck my cap, asshole'
    $form.Focus()
})
$leftPanel.Controls.Add($btnLeftKey)

$lblLeftCps = New-Object System.Windows.Forms.Label
$lblLeftCps.Text      = "$($state.leftCps) CPS"
$lblLeftCps.Location  = New-Object System.Drawing.Point(130, 50)
$lblLeftCps.Size      = New-Object System.Drawing.Size(150, 35)
$lblLeftCps.Font      = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblLeftCps.ForeColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$lblLeftCps.TextAlign = 'MiddleRight'
$leftPanel.Controls.Add($lblLeftCps)

$sliderLeftBg = New-Object System.Windows.Forms.Panel
$sliderLeftBg.Location    = New-Object System.Drawing.Point(15, 95)
$sliderLeftBg.Size        = New-Object System.Drawing.Size(265, 8)
$sliderLeftBg.BackColor   = [System.Drawing.Color]::FromArgb(48, 48, 58)
$sliderLeftBg.BorderStyle = 'None'
$sliderLeftBg.Cursor      = [System.Windows.Forms.Cursors]::Hand

$sliderLeftFill = New-Object System.Windows.Forms.Panel
$sliderLeftFill.Location  = New-Object System.Drawing.Point(0, 0)
$sliderLeftFill.Size      = New-Object System.Drawing.Size(26, 8)
$sliderLeftFill.BackColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$sliderLeftFill.Enabled   = $false
$sliderLeftBg.Controls.Add($sliderLeftFill)

$sliderLeftBg.Add_MouseDown({
    param($s, $e)
    $state.leftBarDrag = $true
    $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 265.0 * 500)))
    $state.leftCps = $nc
    $lblLeftCps.Text = "$($state.leftCps) CPS"
    $sliderLeftFill.Width = [int](265 * ($state.leftCps / 500.0))
    if ($state.leftActive) {
        if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
        $state.leftTimer = New-Object System.Windows.Forms.Timer
        $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
        $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
        $state.leftTimer.Start()
    }
})
$sliderLeftBg.Add_MouseMove({
    param($s, $e)
    if ($state.leftBarDrag) {
        $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 265.0 * 500)))
        $state.leftCps = $nc
        $lblLeftCps.Text = "$($state.leftCps) CPS"
        $sliderLeftFill.Width = [int](265 * ($state.leftCps / 500.0))
        if ($state.leftActive) {
            if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
            $state.leftTimer = New-Object System.Windows.Forms.Timer
            $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
            $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
            $state.leftTimer.Start()
        }
    }
})
$sliderLeftBg.Add_MouseUp({ $state.leftBarDrag = $false })
$leftPanel.Controls.Add($sliderLeftBg)

$lblRightTitle = New-Object System.Windows.Forms.Label
$lblRightTitle.Text      = 'RIGHT CLICK'
$lblRightTitle.Location  = New-Object System.Drawing.Point(15, 130)
$lblRightTitle.Size      = New-Object System.Drawing.Size(270, 25)
$lblRightTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblRightTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblRightTitle.TextAlign = 'MiddleLeft'
$leftPanel.Controls.Add($lblRightTitle)

$btnRightKey = New-Object System.Windows.Forms.Button
$btnRightKey.Text      = 'none'
$btnRightKey.Location  = New-Object System.Drawing.Point(15, 165)
$btnRightKey.Size      = New-Object System.Drawing.Size(100, 35)
$btnRightKey.FlatStyle = 'Flat'
$btnRightKey.FlatAppearance.BorderSize = 0
$btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
$btnRightKey.ForeColor = [System.Drawing.Color]::White
$btnRightKey.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnRightKey.Add_Click({
    $state.waitingRight = $true
    $btnRightKey.Text      = '...'
    $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(100, 80, 120)
    $lblStatus.Text = 'suck my cap, asshole'
    $form.Focus()
})
$leftPanel.Controls.Add($btnRightKey)

$lblRightCps = New-Object System.Windows.Forms.Label
$lblRightCps.Text      = "$($state.rightCps) CPS"
$lblRightCps.Location  = New-Object System.Drawing.Point(130, 165)
$lblRightCps.Size      = New-Object System.Drawing.Size(150, 35)
$lblRightCps.Font      = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$lblRightCps.ForeColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$lblRightCps.TextAlign = 'MiddleRight'
$leftPanel.Controls.Add($lblRightCps)

$sliderRightBg = New-Object System.Windows.Forms.Panel
$sliderRightBg.Location    = New-Object System.Drawing.Point(15, 210)
$sliderRightBg.Size        = New-Object System.Drawing.Size(265, 8)
$sliderRightBg.BackColor   = [System.Drawing.Color]::FromArgb(48, 48, 58)
$sliderRightBg.BorderStyle = 'None'
$sliderRightBg.Cursor      = [System.Windows.Forms.Cursors]::Hand

$sliderRightFill = New-Object System.Windows.Forms.Panel
$sliderRightFill.Location  = New-Object System.Drawing.Point(0, 0)
$sliderRightFill.Size      = New-Object System.Drawing.Size(26, 8)
$sliderRightFill.BackColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$sliderRightFill.Enabled   = $false
$sliderRightBg.Controls.Add($sliderRightFill)

$sliderRightBg.Add_MouseDown({
    param($s, $e)
    $state.rightBarDrag = $true
    $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 265.0 * 500)))
    $state.rightCps = $nc
    $lblRightCps.Text = "$($state.rightCps) CPS"
    $sliderRightFill.Width = [int](265 * ($state.rightCps / 500.0))
    if ($state.rightActive) {
        if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
        $state.rightTimer = New-Object System.Windows.Forms.Timer
        $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
        $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
        $state.rightTimer.Start()
    }
})
$sliderRightBg.Add_MouseMove({
    param($s, $e)
    if ($state.rightBarDrag) {
        $nc = [math]::Max(1, [math]::Min(500, [int]($e.X / 265.0 * 500)))
        $state.rightCps = $nc
        $lblRightCps.Text = "$($state.rightCps) CPS"
        $sliderRightFill.Width = [int](265 * ($state.rightCps / 500.0))
        if ($state.rightActive) {
            if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
            $state.rightTimer = New-Object System.Windows.Forms.Timer
            $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
            $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
            $state.rightTimer.Start()
        }
    }
})
$sliderRightBg.Add_MouseUp({ $state.rightBarDrag = $false })
$leftPanel.Controls.Add($sliderRightBg)

# --- Pannello destro con immagine ---
$rightPanel = New-Object System.Windows.Forms.Panel
$rightPanel.Location  = New-Object System.Drawing.Point(340, 90)
$rightPanel.Size      = New-Object System.Drawing.Size(240, 250)
$rightPanel.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 45)
$rightPanel.BorderStyle = 'None'
$form.Controls.Add($rightPanel)

$picBox = New-Object System.Windows.Forms.PictureBox
$picBox.Location = New-Object System.Drawing.Point(45, 30)
$picBox.Size     = New-Object System.Drawing.Size(150, 150)
$picBox.SizeMode = 'Zoom'
$picBox.BackColor = [System.Drawing.Color]::Transparent
$picBox.BorderStyle = 'None'

if ($state.bgImage) {
    $picBox.Image = $state.bgImage
} else {
    $bmp = New-Object System.Drawing.Bitmap(150, 150)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.FillEllipse([System.Drawing.Brushes]::Purple, 0, 0, 149, 149)
    $g.DrawEllipse([System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(220, 180, 255), 3), 0, 0, 149, 149)
    $font = New-Object System.Drawing.Font('Segoe UI', 40, [System.Drawing.FontStyle]::Bold)
    $g.DrawString('HF', $font, [System.Drawing.Brushes]::White, 30, 40)
    $g.Dispose()
    $picBox.Image = $bmp
}

$rightPanel.Controls.Add($picBox)

$lblImageText = New-Object System.Windows.Forms.Label
$lblImageText.Text      = 'Horror'
$lblImageText.Location  = New-Object System.Drawing.Point(0, 190)
$lblImageText.Size      = New-Object System.Drawing.Size(240, 30)
$lblImageText.Font      = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblImageText.ForeColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$lblImageText.TextAlign = 'MiddleCenter'
$rightPanel.Controls.Add($lblImageText)

$lblImageSub = New-Object System.Windows.Forms.Label
$lblImageSub.Text      = 'Fileless'
$lblImageSub.Location  = New-Object System.Drawing.Point(0, 220)
$lblImageSub.Size      = New-Object System.Drawing.Size(240, 20)
$lblImageSub.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$lblImageSub.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 160)
$lblImageSub.TextAlign = 'MiddleCenter'
$rightPanel.Controls.Add($lblImageSub)

# --- Footer ---
$footer = New-Object System.Windows.Forms.Panel
$footer.Location  = New-Object System.Drawing.Point(0, 355)
$footer.Size      = New-Object System.Drawing.Size(600, 45)
$footer.BackColor = [System.Drawing.Color]::FromArgb(38, 38, 45)
$form.Controls.Add($footer)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'suck my cap, asshole'
$lblStatus.Location  = New-Object System.Drawing.Point(10, 10)
$lblStatus.Size      = New-Object System.Drawing.Size(400, 25)
$lblStatus.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Italic)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 130, 255)
$lblStatus.TextAlign = 'MiddleLeft'
$footer.Controls.Add($lblStatus)

$lblHotkeys = New-Object System.Windows.Forms.Label
$lblHotkeys.Text      = 'F6 (LEFT) | F7 (RIGHT) | F8 (STOP)'
$lblHotkeys.Location  = New-Object System.Drawing.Point(420, 10)
$lblHotkeys.Size      = New-Object System.Drawing.Size(170, 25)
$lblHotkeys.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$lblHotkeys.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 160)
$lblHotkeys.TextAlign = 'MiddleRight'
$footer.Controls.Add($lblHotkeys)

# --- Funzioni di trascinamento ---
$form.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $state.formDrag = $true
        $state.formDragOrigin = $e.Location
    }
})
$form.Add_MouseMove({
    param($s, $e)
    if ($state.formDrag) {
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $e.X - $state.formDragOrigin.X),
            ($form.Location.Y + $e.Y - $state.formDragOrigin.Y)
        )
    }
})
$form.Add_MouseUp({ $state.formDrag = $false; $state.leftBarDrag = $false; $state.rightBarDrag = $false })

$header.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $state.formDrag = $true
        $state.formDragOrigin = New-Object System.Drawing.Point($e.X, $e.Y)
    }
})
$header.Add_MouseMove({
    param($s, $e)
    if ($state.formDrag) {
        $form.Location = New-Object System.Drawing.Point(
            ($form.Location.X + $e.X - $state.formDragOrigin.X),
            ($form.Location.Y + $e.Y - $state.formDragOrigin.Y)
        )
    }
})
$header.Add_MouseUp({ $state.formDrag = $false })

# ============================================================
# Funzioni Autoclicker
# ============================================================
function Toggle-Left {
    $state.leftActive = -not $state.leftActive
    if ($state.leftActive) {
        $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(140, 100, 200)
        $btnLeftKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = 'suck my cap, asshole'
        if ($state.leftTimer) { $state.leftTimer.Stop(); $state.leftTimer.Dispose() }
        $state.leftTimer = New-Object System.Windows.Forms.Timer
        $state.leftTimer.Interval = [math]::Max(1, [int](1000.0 / $state.leftCps))
        $state.leftTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickLeft()" })
        $state.leftTimer.Start()
    } else {
        $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
        $btnLeftKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = 'suck my cap, asshole'
        if ($state.leftTimer) { $state.leftTimer.Stop() }
    }
}

function Toggle-Right {
    $state.rightActive = -not $state.rightActive
    if ($state.rightActive) {
        $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(140, 100, 200)
        $btnRightKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = 'suck my cap, asshole'
        if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
        $state.rightTimer = New-Object System.Windows.Forms.Timer
        $state.rightTimer.Interval = [math]::Max(1, [int](1000.0 / $state.rightCps))
        $state.rightTimer.Add_Tick({ Invoke-Expression "[$($script:uid1)]::ClickRight()" })
        $state.rightTimer.Start()
    } else {
        $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
        $btnRightKey.ForeColor = [System.Drawing.Color]::White
        $lblStatus.Text = 'suck my cap, asshole'
        if ($state.rightTimer) { $state.rightTimer.Stop() }
    }
}

$form.Add_KeyDown({
    param($s, $e)
    $ks = $e.KeyCode.ToString()
    if ($state.waitingLeft) {
        if ($keyMap.ContainsKey($ks)) {
            $state.leftVK         = $keyMap[$ks]
            $btnLeftKey.Text      = $ks
            $btnLeftKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
            $btnLeftKey.ForeColor = [System.Drawing.Color]::White
            $lblStatus.Text = 'suck my cap, asshole'
            $state.waitingLeft  = $false
            $state.skipToggleL  = $true
        }
    } elseif ($state.waitingRight) {
        if ($keyMap.ContainsKey($ks)) {
            $state.rightVK         = $keyMap[$ks]
            $btnRightKey.Text      = $ks
            $btnRightKey.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 68)
            $btnRightKey.ForeColor = [System.Drawing.Color]::White
            $lblStatus.Text = 'suck my cap, asshole'
            $state.waitingRight = $false
            $state.skipToggleR  = $true
        }
    }
})

$state.pollTimer = New-Object System.Windows.Forms.Timer
$state.pollTimer.Interval = 50

$state.pollTimer.Add_Tick({
    if ($state.leftVK -ne 0) {
        $pressed = Invoke-Expression "[$($script:uid2)]::IsPressed($($state.leftVK))"
        if ($pressed -and -not $state.prevKeyL) {
            if (-not $state.skipToggleL) { Toggle-Left } else { $state.skipToggleL = $false }
            $state.prevKeyL = $true
        } elseif (-not $pressed) {
            $state.prevKeyL = $false
        }
    }
    if ($state.rightVK -ne 0) {
        $pressed = Invoke-Expression "[$($script:uid2)]::IsPressed($($state.rightVK))"
        if ($pressed -and -not $state.prevKeyR) {
            if (-not $state.skipToggleR) { Toggle-Right } else { $state.skipToggleR = $false }
            $state.prevKeyR = $true
        } elseif (-not $pressed) {
            $state.prevKeyR = $false
        }
    }
})
$state.pollTimer.Start()

$form.Add_FormClosing({
    if ($state.leftTimer)  { $state.leftTimer.Stop();  $state.leftTimer.Dispose() }
    if ($state.rightTimer) { $state.rightTimer.Stop(); $state.rightTimer.Dispose() }
    if ($state.pollTimer)  { $state.pollTimer.Stop();  $state.pollTimer.Dispose() }
    if ($state.bgImage)    { $state.bgImage.Dispose() }
})

[void]$form.ShowDialog()
