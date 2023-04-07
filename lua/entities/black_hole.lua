AddCSLuaFile()

-- Создаем новую энтити и задаем ей модель
DEFINE_BASECLASS( "base_anim" )

ENT.PrintName = "Black Hole - Eating"
ENT.Category = "Black Hole"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Editable = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar( "Float", 0, "BlackHoleSize", { KeyName = "BlackHoleSize", Edit = { type = "Float", min = 100, max = 10000, order = 1 } } )
    if ( SERVER ) then
        self:NetworkVarNotify( "BlackHoleSize", self.OnBallSizeChanged )
    end
end
if ( SERVER ) then
    function ENT:OnBallSizeChanged( varname, oldvalue, newvalue )
        -- Do not rebuild if the size wasn't changed
        if ( oldvalue == newvalue ) then return end
        self.TargetAttractRadius = newvalue
        self.chtime = RealTime()
    end
end

-- Инициализация энтити
function ENT:Initialize()
    self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WORLD)
    self:SetMaterial("models/shiny")
    self:SetColor(Color(0,0,0,255))

    -- Задаем начальный радиус притяжения и силу притяжения
    self.AttractRadius = 0
    self.TargetAttractRadius = 1000
    self.OldAttractRadius = 0
    self.chtime = RealTime()
    self.BlackHoleMass = (self.AttractRadius / 570) * 50000 * 105
    self.refractMaterial = Material("models/props_c17/fisheyelens")

    self:RebuildPhysics()

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:SetMass(self.BlackHoleMass)
        phys:Wake()
    end
    self:SetNWInt("AttractRadius", self.AttractRadius)
    self:SetBlackHoleSize(self.TargetAttractRadius)
end

function ENT:SpawnFunction( ply, tr, ClassName )

    if ( !tr.Hit ) then return end

    local SpawnPos = tr.HitPos + tr.HitNormal * 100

    -- Make sure the spawn position is not out of bounds
    local oobTr = util.TraceLine( {
        start = tr.HitPos,
        endpos = SpawnPos,
        mask = MASK_SOLID_BRUSHONLY
    } )

    if ( oobTr.Hit ) then
        SpawnPos = oobTr.HitPos + oobTr.HitNormal * ( tr.HitPos:Distance( oobTr.HitPos ) / 2 )
    end

    local ent = ents.Create( ClassName )
    ent:SetPos( SpawnPos )
    ent:Spawn()

    return ent

end

function ENT:RebuildPhysics()
    local size = self:GetNWInt("AttractRadius") / 1000 * 32
    self.BlackHoleMass = (self.AttractRadius / 570) * 50000 * 105
    self:PhysicsInitSphere( size )
    self:SetCollisionBounds( Vector( -size, -size, -size ), Vector( size, size, size ) )
    self:PhysWake()
    --self:SetMoveType(MOVETYPE_NONE)
    if IsValid(self) and IsValid(self:GetPhysicsObject()) then
        self:GetPhysicsObject():EnableGravity(false)
        self:GetPhysicsObject():SetMass(self.BlackHoleMass)
    end
    --self:SetNotSolid( true )
end

-- Обновление энтити
function ENT:Think()
    if SERVER then
        if SERVER then
            self:SetBlackHoleSize(self.TargetAttractRadius)
            self.AttractRadius = Lerp((RealTime() - self.chtime) / 4, self.OldAttractRadius, self.TargetAttractRadius)
            if self.AttractRadius == self.TargetAttractRadius then
                self.OldAttractRadius = self.AttractRadius
            end
            if self.AttractRadius ~= self:GetNWInt("AttractRadius") then
                self:SetNWInt("AttractRadius", self.AttractRadius)
                self:RebuildPhysics()
                self:GetPhysicsObject():SetMass(self.AttractRadius)
                self.AttractStrength = self.AttractRadius
                self:SetNWInt("AttractStrength", self.AttractStrength)
            end
        end
        -- Находим все объекты в заданном радиусе
        local objects = ents.FindInSphere(self:GetPos(), self.AttractRadius)

        -- Притягиваем каждый объект к энтити
        for _, object in pairs(objects) do
            if object ~= self then -- Исключаем саму энтити из притяжения
                if not IsValid(object) or not IsValid(object:GetPhysicsObject()) then continue end
                if object:IsPlayer() and not object:Alive() then return end

                local direction = self:GetPos() - object:GetPos()
                local distance = direction:Length()

                if distance < self:GetNWInt("AttractRadius") / 1000 * 35 then
                    if object:IsPlayer() then
                        object:Kill()
                        continue
                    end
                    if object:GetClass() == "black_hole" or object:GetClass() == "black_hole_nonadmin" then
                        if self.AttractStrength < object:GetNWInt("AttractStrength") then continue end
                        self.TargetAttractRadius = self.TargetAttractRadius + object:GetNWInt("AttractStrength")
                        object:Remove()
                        continue
                    end
                    self.TargetAttractRadius = self.TargetAttractRadius + object:GetPhysicsObject():GetMass()
                    object:Remove()
                    continue
                end

                -- Задаем силу притяжения, которая затухает по мере отдаления от энтити
                local force = direction:GetNormalized() * object:GetPhysicsObject():GetMass() * ((self.AttractRadius - distance) / self.AttractRadius) * 100
                local dt = engine.TickInterval() 

                if object:IsPlayer() or object:IsNPC() then
                    if object:IsOnGround() then
                        object:SetPos(object:GetPos()+Vector(0,0,10))
                    end
                    local zvel = 100-(100 * (distance / self.AttractRadius)) * object:GetPhysicsObject():GetMass()
                    force = force + Vector(0,0,math.max(direction:GetNormalized().z * -zvel, 0))
                end
                if object:IsPlayer() then
                    object:SetVelocity( force * dt )
                end
                if object:IsNPC() then
                    object:SetVelocity( force * dt )
                end
                object:GetPhysicsObject():AddVelocity( force * dt )
            end
        end
        -- Задержка между обновлениями
        self:NextThink(CurTime() + 0.002)
    end
    return true
end

-- Отрисовываем радиус притяжения на клиентах
if CLIENT then
    function ENT:Draw()
        local event_horizon = Color(0, 0, 0, 0)
        local black_hole = Color((math.sin(SysTime()*10)+1)/2*55, 0, 0, 255)
        local affection_radius = Color(255, 0, 0, 15)
        local disk = Color(255, 155, 0)
        local detail = 16

        self.refractMaterial:SetFloat( "$envmap", 0 )
        self.refractMaterial:SetFloat( "$envmaptint", 0 )
        self.refractMaterial:SetInt( "$ignorez", 0 )

        local baserad = self:GetNWInt("AttractRadius")
        local str = 0.5

        baserad = baserad * ((((math.sin(RealTime()) + 1) / 2) / 10 * str) + (1 - (str/10)))

        local size = (baserad / 1000 * 64)

        self:SetRenderBounds(Vector( -size, -size, -size ), Vector( size, size, size ))
        self:DrawShadow(false)
        render.SetColorMaterial()
        local bw = size / 64 * 2
        for i=0+(RealTime()*2),360+(RealTime()*2),1 do
            render.DrawBeam(
                self:GetPos()+(Vector(math.cos(i), math.sin(i), 0)*size*2), 
                self:GetPos()+(Vector(math.cos(i+180), math.sin(i+180), 0)*size*2),
                bw, 0, 1, Color(255, 155, 0))
        end

        self.refractMaterial:SetFloat( "$refractamount", -0.20 )
        render.SetMaterial(self.refractMaterial)
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 64), detail, detail, event_horizon)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 64), detail, detail, event_horizon)

        render.SetColorMaterial()
        --render.DrawSphere(self:GetPos(), (baserad / 1000 * 64), detail, detail, event_horizon)
        --render.DrawSphere(self:GetPos(), (self:GetNWInt("AttractRadius")), detail, detail, affection_radius)
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 32), detail, detail, black_hole)
        --render.DrawSphere(self:GetPos(), -(baserad / 1000 * 64), detail, detail, event_horizon)
        --render.DrawSphere(self:GetPos(), -(self:GetNWInt("AttractRadius")), detail, detail, affection_radius)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 32), detail, detail, black_hole)
    end
end