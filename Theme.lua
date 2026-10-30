StatCapsTheme = {};
StatCapsTheme.profile = { race = "Gondorian", folder = "", colour = { 153, 126, 73 } };

function StatCapsTheme.Configure(profile)
    if (profile) then StatCapsTheme.profile = profile; end
end

function StatCapsTheme.Asset(name)
    return "StatCaps/Resources/" .. StatCapsTheme.profile.folder .. name .. ".tga";
end

function StatCapsTheme.Accent()
    local colour = StatCapsTheme.profile.colour;
    return Turbine.UI.Color(colour[1] / 255, colour[2] / 255, colour[3] / 255);
end

function StatCapsTheme.Badge(parent, x, y)
    if (not StatCapsTheme.profile.class) then return; end
    local badge = Turbine.UI.Control();
    badge:SetParent(parent);
    badge:SetPosition(x, y);
    badge:SetSize(28, 28);
    badge:SetBackground("StatCaps/Resources/class_" .. StatCapsTheme.profile.class .. ".tga");
    badge:SetMouseVisible(false);
end

function StatCapsTheme.Button()
    local button = Turbine.UI.Label();
    button:SetFont(Turbine.UI.Lotro.Font.Verdana12);
    button:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    button:SetWantsKeyEvents(true);
    local hover, pressed, focused = false, false, false;
    local edge = Turbine.UI.Control();
    edge:SetParent(button);
    edge:SetMouseVisible(false);
    edge:SetBackColor(StatCapsTheme.Accent());
    local setSize = button.SetSize;
    button.SetSize = function(self, width, height)
        setSize(self, width, height);
        edge:SetPosition(5, height - 2);
        edge:SetSize(math.max(0, width - 10), 1);
    end;
    local function paint()
        local enabled = button:IsEnabled();
        local state = not enabled and "disabled" or (pressed and "pressed"
            or ((hover or focused) and "hover" or "normal"));
        button:SetBackground(StatCapsTheme.Asset("control_" .. state));
        button:SetBackColor(not enabled and Turbine.UI.Color(0.07, 0.075, 0.08)
            or (pressed and Turbine.UI.Color(0.12, 0.115, 0.09)
                or ((hover or focused) and Turbine.UI.Color(0.22, 0.21, 0.16)
                    or Turbine.UI.Color(0.105, 0.13, 0.145))));
        button:SetForeColor(enabled and Turbine.UI.Color(0.94, 0.88, 0.72)
            or Turbine.UI.Color(0.65, 0.62, 0.54));
    end
    button.EnabledChanged = paint;
    button.MouseEnter = function() hover = true; paint(); end;
    button.MouseLeave = function() hover, pressed = false, false; paint(); end;
    button.MouseDown = function(_, args)
        if (button:IsEnabled() and args.Button == Turbine.UI.MouseButton.Left) then
            pressed = true; button:Focus(); paint();
        end
    end;
    button.MouseUp = function() pressed = false; paint(); end;
    button.MouseClick = function(_, args)
        if (button:IsEnabled() and args.Button == Turbine.UI.MouseButton.Left and button.Click) then button.Click(); end
    end;
    button.KeyDown = function(_, args)
        if (button:IsEnabled() and (args.Key == 13 or args.Key == 32) and button.Click) then button.Click(); end
    end;
    button.FocusGained = function() focused = true; paint(); end;
    button.FocusLost = function() focused, pressed = false, false; paint(); end;
    paint();
    return button;
end

function StatCapsTheme.Window()
    local win = Turbine.UI.Window();
    win:SetBackColor(Turbine.UI.Color(0.045, 0.055, 0.065));
    win:SetWantsKeyEvents(true);
    local header = Turbine.UI.Control();
    header:SetParent(win);
    header:SetBackColor(Turbine.UI.Color(0.095, 0.115, 0.13));
    local title = Turbine.UI.Label();
    title:SetParent(header);
    title:SetPosition(40, 4);
    title:SetMouseVisible(false);
    title:SetFont(Turbine.UI.Lotro.Font.TrajanProBold16 or Turbine.UI.Lotro.Font.Verdana14);
    title:SetForeColor(Turbine.UI.Color(0.93, 0.83, 0.6));
    local line = Turbine.UI.Control();
    line:SetParent(header);
    line:SetPosition(8, 29);
    line:SetBackColor(StatCapsTheme.Accent());
    line:SetMouseVisible(false);
    local close = StatCapsTheme.Button();
    close:SetParent(win);
    close:SetSize(26, 24);
    close:SetText("X");
    close.Click = function() win:SetVisible(false); end;
    local nativeSize = win.SetSize;
    win.SetText = function(self, text)
        self.caption = text;
        title:SetText(text);
    end;
    win.SetSize = function(self, width, height)
        nativeSize(self, width, height);
        header:SetSize(width, 32);
        header:SetBackground(StatCapsTheme.Asset("window_header_" .. width));
        title:SetSize(math.max(0, width - 113), 23);
        line:SetSize(math.max(0, width - 16), 1);
        close:SetPosition(width - 33, 3);
        if (not self.classBadgeAdded) then
            StatCapsTheme.Badge(header, width - 65, 2);
            self.classBadgeAdded = true;
        end
    end;
    local moving, mx, my, left, top;
    header.MouseDown = function(_, args)
        if (args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        moving = true;
        mx, my = Turbine.UI.Display.GetMousePosition();
        left, top = win:GetLeft(), win:GetTop();
        win:Activate();
    end;
    header.MouseMove = function()
        if (not moving) then return; end
        local x, y = Turbine.UI.Display.GetMousePosition();
        local width, height = Turbine.UI.Display.GetSize();
        win:SetPosition(math.max(0, math.min(left + x - mx, width - win:GetWidth())),
            math.max(0, math.min(top + y - my, height - 32)));
    end;
    header.MouseUp = function() moving = false; end;
    win.VisibleChanged = function() moving = false; end;
    win.KeyDown = function(_, args) if (args.Key == 27) then win:SetVisible(false); end end;
    return win;
end

function StatCapsTheme.Panel(parent, width, height)
    local panel = Turbine.UI.Control();
    panel:SetParent(parent);
    panel:SetPosition(12, 35);
    panel:SetBackColor(Turbine.UI.Color(0.055, 0.06, 0.065));
    panel:SetMouseVisible(false);
    local trim = {};
    for index = 1, 12 do
        local line = Turbine.UI.Control();
        line:SetParent(panel);
        line:SetMouseVisible(false);
        line:SetBackColor(index <= 4 and Turbine.UI.Color(0.3, 0.27, 0.19)
            or StatCapsTheme.Accent());
        trim[index] = line;
    end
    local function place(index, x, y, w, h)
        trim[index]:SetPosition(x, y);
        trim[index]:SetSize(w, h);
    end
    local function resize(w, h)
        w, h = w - 24, h - 50;
        panel:SetSize(w, h);
        place(1, 0, 0, w, 1);
        place(2, 0, h - 1, w, 1);
        place(3, 0, 0, 1, h);
        place(4, w - 1, 0, 1, h);
        for corner = 0, 3 do
            local x = corner % 2 == 0 and 4 or w - 22;
            local y = corner < 2 and 4 or h - 5;
            place(5 + corner * 2, x, y, 18, 1);
            place(6 + corner * 2, corner % 2 == 0 and 4 or w - 5,
                corner < 2 and 4 or h - 22, 1, 18);
        end
    end
    resize(width, height);
    return resize;
end
