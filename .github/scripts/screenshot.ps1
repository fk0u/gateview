# Full-desktop screenshot that includes layered/transparent windows (CopyFromScreen can't: it
# rejects the CAPTUREBLT flag). Usage: pwsh screenshot.ps1 out.png
param([string]$Out = "smoke-screenshot.png")
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Win32 -Name Cap -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetDC(System.IntPtr hwnd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int ReleaseDC(System.IntPtr hwnd, System.IntPtr dc);
[System.Runtime.InteropServices.DllImport("gdi32.dll")] public static extern bool BitBlt(System.IntPtr dst, int x, int y, int w, int h, System.IntPtr src, int sx, int sy, int rop);
'@
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dst = $g.GetHdc(); $src = [Win32.Cap]::GetDC([IntPtr]::Zero)
[void][Win32.Cap]::BitBlt($dst, 0, 0, $b.Width, $b.Height, $src, $b.X, $b.Y, (0x00CC0020 -bor 0x40000000))
[void][Win32.Cap]::ReleaseDC([IntPtr]::Zero, $src); $g.ReleaseHdc($dst); $g.Dispose()
$bmp.Save($Out)
