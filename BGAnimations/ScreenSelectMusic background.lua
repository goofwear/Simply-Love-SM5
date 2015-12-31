return Def.ActorFrameTexture{
	Name="Screenshot_AFT",
	InitCommand=function(self)
		self:SetHeight( PREFSMAN:GetPreference("DisplayHeight") )
			:SetWidth( PREFSMAN:GetPreference("DisplayHeight") * PREFSMAN:GetPreference("DisplayAspectRatio")  )
			:Create()
			:visible(false)
	end,
	RenderCommand=function(self)
		self:visible(true):Draw():visible(false)
		SL.Global.ScreenshotTexture = self:GetTexture()
	end,

	Def.ActorProxy{
		Name="Overlay_Screenshot",
		OnCommand=function(self)
			self:SetTarget( SCREENMAN:GetTopScreen() )
		end,
		ScreenshotCurrentScreenMessageCommand=function(self)
			self:GetParent():queuecommand("Render")
		end
	}
}