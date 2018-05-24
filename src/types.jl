# this is a bit of a weird name, but all scenes and plots are transformable
# so that's what they all have in common. This might be better expressed as traits
abstract type Transformable end
abstract type AbstractPlot{Typ} <: Transformable end
abstract type AbstractScene <: Transformable end
abstract type ScenePlot{Typ} <: AbstractPlot{Typ} end

const SceneLike = Union{AbstractScene, ScenePlot}
const Attributes = Dict{Symbol, Any}

abstract type AbstractCamera end

# placeholder if no camera is present
struct EmptyCamera <: AbstractCamera end

@enum RaymarchAlgorithm IsoValue Absorption MaximumIntensityProjection AbsorptionRGBA IndexedAbsorptionRGBA

const RealVector{T} = AbstractVector{T} where T <: Number

const Node = Signal

const Rect{N, T} = HyperRectangle{N, T}
const Rect2D{T} = HyperRectangle{2, T}
const FRect2D = Rect2D{Float32}

const Rect3D{T} = Rect{3, T}
const FRect3D = Rect3D{Float32}
const IRect3D = Rect3D{Int}


const IRect2D = Rect2D{Int}

const Point2d{T} = NTuple{2, T}
const Vec2d{T} = NTuple{2, T}
const VecTypes{N, T} = Union{StaticVector{N, T}, NTuple{N, T}}
const RGBAf0 = RGBA{Float32}


abstract type AbstractScreen end


function IRect(x, y, w, h)
    HyperRectangle{2, Int}(Vec(round(Int, x), round(Int, y)), Vec(round(Int, w), round(Int, h)))
end
function IRect(xy::VecTypes, w, h)
    IRect(xy[1], xy[2], w, h)
end
function IRect(x, y, wh::VecTypes)
    IRect(x, y, wh[1], wh[2])
end
function IRect(xy::VecTypes, wh::VecTypes)
    IRect(xy[1], xy[2], wh[1], wh[2])
end

function positive_widths(rect::HyperRectangle{N, T}) where {N, T}
    mini, maxi = minimum(rect), maximum(rect)
    realmin = min.(mini, maxi)
    realmax = max.(mini, maxi)
    HyperRectangle{N, T}(realmin, realmax .- realmin)
end

function FRect(x, y, w, h)
    HyperRectangle{2, Float32}(Vec2f0(x, y), Vec2f0(w, h))
end
function FRect(r::SimpleRectangle)
    FRect(r.x, r.y, r.w, r.h)
end
function FRect(r::Rect)
    FRect(minimum(r), widths(r))
end
function FRect(xy::VecTypes, w, h)
    FRect(xy[1], xy[2], w, h)
end
function FRect(x, y, wh::VecTypes)
    FRect(x, y, wh[1], wh[2])
end
function FRect(xy::VecTypes, wh::VecTypes)
    FRect(xy[1], xy[2], wh[1], wh[2])
end

function FRect3D(x::Tuple{Tuple{<: Number, <: Number}, Tuple{<: Number, <: Number}})
    FRect3D(Vec3f0(x[1]..., 0), Vec3f0(x[2]..., 0))
end
function FRect3D(x::Tuple{Tuple{<: Number, <: Number, <: Number}, Tuple{<: Number, <: Number, <: Number}})
    FRect3D(Vec3f0(x[1]...), Vec3f0(x[2]...))
end

function FRect3D(x::Rect2D)
    FRect3D(Vec3f0(minimum(x)..., 0), Vec3f0(widths(x)..., 0.0))
end
# For now, we use Reactive.Signal as our Node type. This might change in the future
const Node = Signal

include("interaction/iodevices.jl")

struct Events
    window_area::Node{IRect2D}
    window_dpi::Node{Float64}
    window_open::Node{Bool}

    mousebuttons::Node{Set{Mouse.Button}}
    mouseposition::Node{Point2d{Float64}}
    mousedrag::Node{Mouse.DragEnum}
    scroll::Node{Vec2d{Float64}}

    keyboardbuttons::Node{Set{Keyboard.Button}}

    unicode_input::Node{Vector{Char}}
    dropped_files::Node{Vector{String}}
    hasfocus::Node{Bool}
    entered_window::Node{Bool}
end

function Events()
    Events(
        node(:window_area, IRect(0, 0, 1, 1)),
        node(:window_dpi, 100.0),
        node(:window_open, false),

        node(:mousebuttons, Set{Mouse.Button}()),
        node(:mouseposition, (0.0, 0.0)),
        node(:mousedrag, Mouse.notpressed),
        node(:scroll, (0.0, 0.0)),

        node(:keyboardbuttons, Set{Keyboard.Button}()),

        node(:unicode_input, Char[]),
        node(:dropped_files, String[]),
        node(:hasfocus, false),
        node(:entered_window, false),
    )
end

mutable struct Camera
    view::Node{Mat4f0}
    projection::Node{Mat4f0}
    projectionview::Node{Mat4f0}
    resolution::Node{Vec2f0}
    eyeposition::Node{Vec3f0}
    steering_nodes::Vector{Node}
end

struct Transformation
    translation::Node{Vec3f0}
    scale::Node{Vec3f0}
    rotation::Node{Quaternionf0}
    model::Node{Mat4f0}
    flip::Node{NTuple{3, Bool}}
    align::Node{Vec2f0}
    func::Node{Any}
end

# There are only two types of plots. Atomic Plots, which are the most basic building blocks.
# Then you can combine them to form more complex plots in the form of a Combined plot.
struct Atomic{Typ, T} <: AbstractPlot{Typ}
    parent::SceneLike
    transformation::Transformation
    attributes::Attributes
    input_args::Tuple # we push new values to this
    output_args::Tuple # these are the arguments we actually work with in the backend/recipe
end

struct Combined{Typ, T} <: ScenePlot{Typ}
    parent::SceneLike
    transformation::Transformation
    attributes::Attributes
    input_args::Tuple
    output_args::Tuple
    plots::Vector{AbstractPlot}
end

parent(x::AbstractPlot) = x.parent

basetype(::Type{<: Combined}) = Combined
basetype(::Type{<: Atomic}) = Atomic

plotkey(::Type{<: AbstractPlot{Typ}}) where Typ = Symbol(lowercase(string(Typ)))
plotkey(::T) where T <: AbstractPlot = plotkey(T)

plotfunc(::Type{<: AbstractPlot{Func}}) where Func = Func
plotfunc(::T) where T <: AbstractPlot = plotfunc(T)
plotfunc(f::Function) = f

plotfunc2type(x::T) where T = plotfunc2type(T)
plotfunc2type(x::Type{<: AbstractPlot}) = x
plotfunc2type(f::Function) = Combined{f}

"""
Billboard attribute to always have a primitive face the camera.
Can be used for rotation.
"""
immutable Billboard end

const Vecf0{N} = Vec{N, Float32}
const Pointf0{N} = Point{N, Float32}
export Vecf0, Pointf0
const NativeFont = Vector{Ptr{FreeType.FT_FaceRec}}