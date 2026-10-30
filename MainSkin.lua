StatCapsMainSkin = {};

local function Art(control, name)
    control:SetBackground(StatCapsTheme.Asset(name));
end

function StatCapsMainSkin.Button(parent, text, x, y, kind)
    local button = Turbine.UI.Label();
    local width = kind == "tier" and 125 or (kind == "close" and 28 or 255);
    local height = kind == "tier" and 30 or (kind == "close" and 28 or 32);
    button:SetParent(parent);
    button:SetPosition(x, y);
    button:SetSize(width, height);
    button:SetFont(Turbine.UI.Lotro.Font.Verdana14);
    button:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter);
    button:SetText(StatCapsLocalization.Text(text));
    button:SetWantsKeyEvents(true);
    local selected, hovering, pressed, focused = false, false, false, false;
    local function paint()
        local enabled = button:IsEnabled();
        local state = not enabled and "disabled" or (selected and "selected" or
            (pressed and "pressed" or ((hovering or focused) and "hover" or "normal")));
        Art(button, kind .. "_" .. state);
        button:SetForeColor(not enabled and Turbine.UI.Color(0.55, 0.54, 0.5)
            or (selected and Turbine.UI.Color(1, 0.9, 0.64) or Turbine.UI.Color(0.92, 0.88, 0.77)));
    end
    button.SetSelected = function(_, value) selected = value; paint(); end;
    button.EnabledChanged = paint;
    button.MouseEnter = function() hovering = true; paint(); end;
    button.MouseLeave = function() hovering, pressed = false, false; paint(); end;
    button.MouseDown = function(_, args)
        if (button:IsEnabled() and args.Button == Turbine.UI.MouseButton.Left) then
            pressed = true;
            button:Focus();
            paint();
        end
    end;
    button.MouseUp = function() pressed = false; paint(); end;
    button.MouseClick = function(_, args)
        if (button:IsEnabled() and args.Button == Turbine.UI.MouseButton.Left and button.Click) then
            button.Click();
        end
    end;
    button.FocusGained = function() focused = true; paint(); end;
    button.FocusLost = function() focused, pressed = false, false; paint(); end;
    button.KeyDown = function(_, args)
        if (button:IsEnabled() and (args.Key == 13 or args.Key == 32) and button.Click) then
            button.Click();
        end
    end;
    paint();
    return button;
end

function StatCapsMainSkin.Window(onMoved)
    local win = Turbine.UI.Window();
    win:SetSize(550, 180);
    win:SetBackColor(Turbine.UI.Color(0.045, 0.055, 0.065));
    win:SetWantsKeyEvents(true);
    local header = Turbine.UI.Control();
    header:SetParent(win);
    header:SetSize(550, 78);
    Art(header, "main_header");
    StatCapsTheme.Badge(win, 367, 40);
    local title = Turbine.UI.Label();
    title:SetParent(win);
    title:SetPosition(83, 13);
    title:SetSize(315, 25);
    title:SetText(StatCapsLocalization.Text("Stat Caps"));
    title:SetFont(Turbine.UI.Lotro.Font.TrajanProBold20 or Turbine.UI.Lotro.Font.Verdana18);
    title:SetForeColor(Turbine.UI.Color(0.93, 0.83, 0.6));
    title:SetMouseVisible(false);
    local close = StatCapsMainSkin.Button(win, "X", 507, 12, "close");
    close.Click = function() win:SetVisible(false); end;
    local left, right, bottom = Turbine.UI.Control(), Turbine.UI.Control(), Turbine.UI.Control();
    for _, control in ipairs({ left, right, bottom }) do
        control:SetParent(win);
        control:SetMouseVisible(false);
    end
    left:SetBackColor(StatCapsTheme.Accent());
    right:SetBackColor(StatCapsTheme.Accent());
    Art(bottom, "main_bottom");
    local moving, startX, startY, startLeft, startTop;
    header.MouseDown = function(_, args)
        if (args.Button ~= Turbine.UI.MouseButton.Left) then return; end
        moving = true;
        startX, startY = Turbine.UI.Display.GetMousePosition();
        startLeft, startTop = win:GetLeft(), win:GetTop();
        win:Activate();
    end;
    local function clamp(x, y)
        local width, height = Turbine.UI.Display.GetSize();
        return math.max(0, math.min(x, width - 550)),
            math.max(0, math.min(y, height - win:GetHeight()));
    end
    header.MouseMove = function()
        if (not moving) then return; end
        local x, y = Turbine.UI.Display.GetMousePosition();
        win:SetPosition(clamp(startLeft + x - startX, startTop + y - startY));
    end;
    header.MouseUp = function()
        if (not moving) then return; end
        moving = false;
        onMoved();
    end;
    win.KeyDown = function(_, args)
        if (args.Key == 27) then win:SetVisible(false); end
    end;
    win.VisibleChanged = function() moving = false; end;
    local function resize(_, height)
        win:SetHeight(height);
        left:SetPosition(2, 78);
        left:SetSize(1, math.max(0, height - 90));
        right:SetPosition(547, 78);
        right:SetSize(1, math.max(0, height - 90));
        bottom:SetPosition(0, height - 14);
        bottom:SetSize(550, 14);
        win:SetPosition(clamp(win:GetLeft(), win:GetTop()));
    end
    resize(550, 180);
    return win, resize;
end
