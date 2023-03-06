AddCSLuaFile()

-- Создаем новую энтити и задаем ей модель
DEFINE_BASECLASS( "base_anim" )

ENT.PrintName = "Black Hole - Not Eating"
ENT.Category = "Black Hole"

ENT.Spawnable = true
ENT.AdminOnly = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

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
    self.TargetAttractRadius = 500
    self.AttractStrength = 5000
    self.refractMaterial = Material("models/props_c17/fisheyelens")

    self:RebuildPhysics()

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
    end
    self:SetNWInt("AttractRadius", self.AttractRadius)
    if CLIENT then
        local radius = self.AttractRadius
        local vOffset = self:GetPos()

        local emitter = ParticleEmitter( vOffset )
        timer.Create("BlackHoleDisk"..self:EntIndex(), 0.1, 0, function()
            if not IsValid(self) then
                return
            end

            local Low, High = self:WorldSpaceAABB()
            local size = High.x - Low.x
            Low.y = Low.y - size
            High.y = High.y + size
            Low.x = Low.x - size
            High.x = High.x + size
            for i=0,50 do
                local vPos = Vector( math.Rand( Low.x, High.x ), math.Rand( Low.y, High.y ), (Low.z + High.z) / 2 )
                local particle = emitter:Add( "effects/spark", vPos )
                if ( particle ) then
                    local vel = ((self:GetPos() - vPos) / 2)
                    vel:Rotate(Angle(0,90,0))
                    particle:SetVelocity( vel )
                    particle:SetLifeTime( 0 )
                    particle:SetDieTime( 2 )
                    particle:SetStartAlpha( 255 )
                    particle:SetEndAlpha( 0 )
                    particle:SetStartSize( 5 )
                    particle:SetEndSize( 0 )
                    --particle:SetRoll( math.Rand(0, 360) )
                    particle:SetRollDelta( 0 )
                    particle:SetRoll(90)
                    particle:SetColor(math.random(200,255), math.random(0,155), 0)

                    particle:SetAirResistance( 0 )
                    particle:SetGravity( vel )
                    particle:SetCollide( false )

                end
            end
        end)
    end
end

function ENT:SpawnFunction( ply, tr, ClassName )

    if ( !tr.Hit ) then return end

    local SpawnPos = tr.HitPos + tr.HitNormal * 10

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
    self:PhysicsInitSphere( size )
    self:SetCollisionBounds( Vector( -size, -size, -size ), Vector( size, size, size ) )
    self:PhysWake()
    --self:SetMoveType(MOVETYPE_NONE)
    if IsValid(self) and IsValid(self:GetPhysicsObject()) then
        self:GetPhysicsObject():EnableGravity(false)
    end
    --self:SetNotSolid( true )
end

-- Обновление энтити
function ENT:Think()
    if SERVER then
        self.AttractRadius = self.AttractRadius + math.floor((self.TargetAttractRadius - self.AttractRadius) / 50)
        if self.AttractRadius ~= self:GetNWInt("AttractRadius") then
            self:SetNWInt("AttractRadius", self.AttractRadius)
            self:RebuildPhysics()
            self:GetPhysicsObject():SetMass(self.AttractRadius)
        end
        if self.AttractStrength ~= self:GetNWInt("AttractStrength") then
            self:SetNWInt("AttractStrength", self.AttractStrength)
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

                -- Задаем силу притяжения, которая затухает по мере отдаления от энтити
                local force = direction:GetNormalized() * (self.AttractStrength * (self.AttractRadius - distance) / self.AttractRadius) + (Vector(0,0,-1) - direction:GetNormalized() * -600)
                local dt = engine.TickInterval() 

                if object:IsPlayer() then
                    local act = object:GetActivity()
                    if act < 48 && act > -2 && (act < 20 || act > 24) then
                        object:SetVelocity( force * dt )
                    else
                        object:SetVelocity( force * dt + object:GetVelocity() )
                    end
                end

                object:GetPhysicsObject():AddVelocity( force * dt )
            end
        end

        -- Задержка между обновлениями
        self:NextThink(CurTime() + 0.01)
    end
    return true
end

-- Отрисовываем радиус притяжения на клиентах
if CLIENT then
    function ENT:Draw()
        local event_horizon = Color(0, 127, 255, 55)
        local black_hole = Color(0, 0, 0, 255)
        local affection_radius = Color(255, 0, 0, 15)
        --self:DrawModel()

        local baserad = self:GetNWInt("AttractRadius")
        local str = 0.5

        baserad = baserad * ((((math.sin(RealTime()) + 1) / 2) / 10 * str) + (1 - (str/10)))

        for mul=64,33, -10 do
            self.refractMaterial:SetFloat( "$refractamount", 1/(mul/4) )
            render.SetMaterial(self.refractMaterial)
            render.DrawSphere(self:GetPos(), (baserad / 1000 * mul), 50, 50, event_horizon)
            render.DrawSphere(self:GetPos(), -(baserad / 1000 * mul), 50, 50, event_horizon)
        end

        render.SetColorMaterial()
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 64), 50, 50, event_horizon)
        render.DrawSphere(self:GetPos(), (self:GetNWInt("AttractRadius")), 50, 50, affection_radius)
        render.DrawSphere(self:GetPos(), (baserad / 1000 * 32), 50, 50, black_hole)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 64), 50, 50, event_horizon)
        render.DrawSphere(self:GetPos(), -(self:GetNWInt("AttractRadius")), 50, 50, affection_radius)
        render.DrawSphere(self:GetPos(), -(baserad / 1000 * 32), 50, 50, black_hole)
    end
end