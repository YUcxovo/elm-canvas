module Canvas exposing
    ( CanvasValue
    , toHtml, toHtmlWith
    , Renderable, Point
    , clear, shapes, text, texture, group, empty
    , Shape
    , rect, roundRect, circle, arc, path
    , PathSegment, arcTo, bezierCurveTo, lineTo, moveTo, quadraticCurveTo
    )

{-| This module exposes a nice drawing API that works on top of the the DOM
canvas.

See instructions in the main page of the package for installation, as it
requires the `elm-canvas` web component to work.


# Canvas value

@docs CanvasValue


# Usage in HTML

@docs toHtml, toHtmlWith


# Drawing things

@docs Renderable, Point

@docs clear, shapes, text, texture, group, empty


# Drawing shapes

Shapes can be rectangles, circles, and different types of lines. By composing
shapes, you can draw complex figures! There are many functions that produce
a `Shape`, which you can feed to `shapes` to get something on the screen.

@docs Shape

Here are the different functions that produce shapes that we can draw.

@docs rect, roundRect, circle, arc, path


## Paths

In order to make a complex path, we need to put together a list of `PathSegment`

@docs PathSegment, arcTo, bezierCurveTo, lineTo, moveTo, quadraticCurveTo

-}

import Canvas.Internal.Canvas as C exposing (..)
import Canvas.Internal.CustomElementJsonApi as CE exposing (Command, Commands, commands)
import Canvas.Internal.Texture as T
import Canvas.Path2D as Path exposing (renderShape)
import Canvas.Texture as Texture exposing (Texture)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (on)
import Html.Keyed as Keyed
import Json.Decode as D
import Json.Encode as E



-- Canvas Value


{-| The data type for return values needed from main elm code.

label is for identify the target, every time you use a js function with return
value or store some data, you need a label to get it in next frame.

valuetype is the data type of the return value.

**Note**: the valuetype of a stored data is **storeValue**

value is the value you need.

-}
type alias CanvasValue =
    { label : String
    , valuetype : String
    , value : E.Value
    }



-- HTML


{-| Create a Html element that you can use in your view.

    Canvas.toHtml ( width, height )
        ( model.canvasReturnValue, Canvas )
        [ style "display" "block", onClick CanvasClick ]
        [ shapes [ fill Color.white ] [ rect ( 0, 0 ) w h ]
        , text
            [ font { style = "", size = 48, family = "sans-serif" }, align Center ]
            ( 50, 50 )
            "Hello world"
        ]

`toHtml` is almost like creating other Html elements. We need to pass `(width,
height)` in pixels, the `CanvasValue` list that receive from canvas which might be stored
in your model, the way you change the canvas value to a msg which you defined
in the Msg part, a list of `Html.Attribute`, and finally _instead_ of a list
of html elements, we pass a `List Renderable`. A `Renderable` is a thing that
the canvas knows how to render. Read on for more information 👇.

**Note**: Remember to include the `elm-canvas` web component from npm in your page for
this to work!

**Note**: This element has `display: inline` by default, so their width or
height will have no effect. You can change it to `block` for example. See [MDN:
display](https://developer.mozilla.org/es/docs/Web/CSS/display) for possible
display values.

-}
toHtml : ( Int, Int ) -> ( List CanvasValue, CanvasValue -> msg ) -> List (Attribute msg) -> List Renderable -> Html msg
toHtml ( w, h ) ( retvalues, toMsg ) attrs entities =
    toHtmlWith
        { width = w
        , height = h
        , textures = []
        , returnValues = ( retvalues, toMsg )
        }
        attrs
        entities


{-| Similar to `toHtml` but with more explicit options and the ability to load
textures.

    Canvas.toHtmlWith
        { width = 500
        , height = 500
        , textures = [ Texture.loadImageUrl "./assets/sprite.png" TextureLoaded ]
        , returnValues = ( model.canvasReturnValue, Canvas )
        }
        [ style "display" "block", onClick CanvasClick ]
        [ shapes [ fill Color.white ] [ rect ( 0, 0 ) w h ]
        , text
            [ font { style = "", size = 48, family = "sans-serif" }, align Center ]
            ( 50, 50 )
            "Hello world"
        ]

**Note**: Remember to include the `elm-canvas` web component from npm in your page for
this to work!

**Note**: This element has `display: inline` by default, so their width or
height will have no effect. You can change it to `block` for example. See [MDN:
display](https://developer.mozilla.org/es/docs/Web/CSS/display) for possible
display values.

See `toHtml` above and the `Canvas.Texture` module for more details.

-}
toHtmlWith :
    { width : Int
    , height : Int
    , textures : List (Texture.Source msg)
    , returnValues : ( List CanvasValue, CanvasValue -> msg )
    }
    -> List (Attribute msg)
    -> List Renderable
    -> Html msg
toHtmlWith options attrs entities =
    let
        ( retvalues, valuetoMsg ) =
            options.returnValues

        returnValueDecoder : (CanvasValue -> msg) -> D.Decoder msg
        returnValueDecoder toMsg =
            D.map (\canvasReturnValue -> toMsg canvasReturnValue) <|
                D.map3 CanvasValue
                    (D.at [ "detail", "label" ] D.string)
                    (D.at [ "detail", "valuetype" ] D.string)
                    (D.at [ "detail", "value" ] D.value)

        eventListener =
            on "canvasReturnValue" (returnValueDecoder valuetoMsg)
    in
    Keyed.node "elm-canvas"
        (commands (render entities retvalues) :: height options.height :: width options.width :: eventListener :: attrs)
        (( "__canvas", cnvs )
            :: List.map renderTextureSource options.textures
        )


cnvs : Html msg
cnvs =
    canvas [] []



-- Types


{-| A small alias to reference points on some of the functions on the package.

The first argument of the tuple is the `x` position, and the second is the `y`
position.

    -- Making a point with x = 15 and y = 55
    point : Point
    point =
        ( 15, 55 )

-}
type alias Point =
    ( Float, Float )


{-| A `Renderable` is a thing that the canvas knows how to render, similar to
`Html` elements.

We can make `Renderable`s to use with `Canvas.toHtml` with functions like
`shapes` and `text`.

-}
type alias Renderable =
    C.Renderable


mergeDrawOp : DrawOp -> DrawOp -> DrawOp
mergeDrawOp op1 op2 =
    case ( op1, op2 ) of
        ( Fill _, Fill c ) ->
            Fill c

        ( Stroke _, Stroke c ) ->
            Stroke c

        ( Fill c1, Stroke c2 ) ->
            FillAndStroke c1 c2

        ( Stroke c1, Fill c2 ) ->
            FillAndStroke c2 c1

        ( _, FillAndStroke c sc ) ->
            FillAndStroke c sc

        ( FillAndStroke _ sc, Fill c2 ) ->
            FillAndStroke c2 sc

        ( FillAndStroke c _, Stroke sc2 ) ->
            FillAndStroke c sc2

        ( NotSpecified, whatever ) ->
            whatever

        ( whatever, NotSpecified ) ->
            whatever



-- Clear


{-| We use `clear` to remove the contents of a rectangle in the screen and make
them transparent.

    import Canvas exposing (..)

    Canvas.toHtml ( width, height )
        []
        [ clear ( 0, 0 ) width height
        , shapes [ fill Color.red ] [ rect ( 10, 10 ) 20 20 ]
        ]

-}
clear : Point -> Float -> Float -> Renderable
clear point w h =
    Renderable
        { commands = []
        , drawOp = NotSpecified
        , drawable = DrawableClear point w h
        }



-- Shapes drawables


{-| A `Shape` represents a shape or lines to be drawn. Giving them to `shapes`
we get a `Renderable` for the canvas.

    shapes []
        [ path ( 20, 10 )
            [ lineTo ( 10, 30 )
            , lineTo ( 30, 30 )
            , lineTo ( 20, 10 )
            ]
        , circle ( 50, 50 ) 10
        , rect ( 100, 150 ) 40 50
        , circle ( 100, 100 ) 80
        ]

-}
type alias Shape =
    C.Shape


{-| In order to draw a path, you need to give the function `path` a list of
`PathSegment`
-}
type alias PathSegment =
    C.PathSegment


{-| We use `shapes` to render different shapes like rectangles, circles, and
lines of different kinds that we can connect together.

You can draw many shapes with the same `Setting`s, which makes for very
efficient rendering.

    import Canvas exposing (..)
    import Color -- elm install avh4/elm-color

    Canvas.toHtml ( width, height )
        []
        [ shapes [ fill Color.white ] [ rect ( 0, 0 ) width height ] ]

You can read more about the different kinds of `Shape` in the **Drawing shapes**
section.

-}
shapes : List Setting -> List Shape -> Renderable
shapes settings ss =
    addSettingsToRenderable settings
        (Renderable
            { commands = []
            , drawOp = NotSpecified
            , drawable = DrawableShapes ss
            }
        )


addSettingsToRenderable : List Setting -> Renderable -> Renderable
addSettingsToRenderable settings renderable =
    let
        addSetting : Setting -> Renderable -> Renderable
        addSetting setting (Renderable r) =
            Renderable <|
                case setting of
                    SettingCommand cmd ->
                        { r | commands = cmd :: r.commands }

                    SettingCommands cmds ->
                        { r | commands = List.foldl (::) r.commands cmds }

                    SettingUpdateDrawable f ->
                        { r | drawable = f r.drawable }

                    SettingDrawOp op ->
                        { r | drawOp = mergeDrawOp r.drawOp op }
    in
    List.foldl addSetting renderable settings


{-| Creates the shape of a rectangle. It needs the position of the top left
corner, the width, and the height.

    rect pos width height

-}
rect : Point -> Float -> Float -> Shape
rect pos width height =
    Rect pos width height


{-| Creates the shape of a rounded rectangle.
It takes the position of the top left corner, the width, the height and a list specifying
the radii of the circular arc to be used for the corners of the rectangle. The list must
contain between 1 and 4 positive numbers.
You can find more info on this [page](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/roundRect).
-}
roundRect : Point -> Float -> Float -> List Float -> Shape
roundRect pos width height radii =
    RoundRect pos width height radii


{-| Creates a circle. It takes the position of the center of the circle, and the
radius of it.

    circle pos radius

-}
circle : Point -> Float -> Shape
circle pos radius =
    Circle pos radius


{-| Creates a complex path as a shape from a list of `PathSegment` instructions.

It is mandatory to pass in the starting point for the path, since the path
starts with an implicit `moveTo` the starting point to avoid undesirable
behavior and implicit state.

    path startingPoint segments

-}
path : Point -> List PathSegment -> Shape
path startingPoint segments =
    Path startingPoint segments


{-| Creates an arc, a partial circle. It takes:

  - The position of the center of the circle
  - The radius of the circle
  - The start angle (in radians) where the arc will start
      - 0 is center right, 90 is bottom center
  - The end angle (in radians) where the arc will end
  - If it should draw in clockwise or anti-clockwise direction

**Note**: If you want to give the angles in degrees, you can use the `degrees`
function from elm/core.

    arc ( 10, 10 ) 40 { startAngle = degrees 15, endAngle = degrees 85, clockwise = True }

**Note**: If you want to make a partial circle (like a pizza slice), combine
with `path` to make a triangle, and then the arc. See the pie chart example.

-}
arc : Point -> Float -> { startAngle : Float, endAngle : Float, clockwise : Bool } -> Shape
arc pos radius { startAngle, endAngle, clockwise } =
    Arc pos radius startAngle endAngle (not clockwise)


{-| Adds an arc to the path with the given control points and radius.

The arc drawn will be a part of a circle, never elliptical. Typical use could be
making a rounded corner.

One way to think about the arc drawn is to imagine two straight segments, from
the starting point (latest point in current path) to the first control point,
and then from the first control point to the second control point. These two
segments form a sharp corner with the first control point being in the corner.
Using `arcTo`, the corner will instead be an arc with the given radius.

The arc is tangential to both segments, which can sometimes produce surprising
results, e.g. if the radius given is larger than the distance between the
starting point and the first control point.

If the radius specified doesn't make the arc meet the starting point (latest
point in the current path), the starting point is connected to the arc with
a straight line segment.

    arcTo ( x1, y1 ) ( x2, y2 ) radius

You can see more examples and docs in [this page](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/arcTo)

-}
arcTo : Point -> Point -> Float -> PathSegment
arcTo pos1 pos2 radius =
    ArcTo pos1 pos2 radius


{-| Adds a cubic Bézier curve to the path. It requires three points. The first
two points are control points and the third one is the end point. The starting
point is the last point in the current path, which can be changed using `moveTo`
before creating the Bézier curve. You can learn more about this curve in the
[MDN docs](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/bezierCurveTo).

    bezierCurveTo controlPoint1 controlPoint2 point

    bezierCurveTo ( cp1x, cp1y ) ( cp2x, cp2y ) ( x, y )

  - `cp1x`
      - The x axis of the coordinate for the first control point.
  - `cp1y`
      - The y axis of the coordinate for the first control point.
  - `cp2x`
      - The x axis of the coordinate for the second control point.
  - `cp2y`
      - The y axis of the coordinate for the second control point.
  - `x`
      - The x axis of the coordinate for the end point.
  - `y`
      - The y axis of the coordinate for the end point.

-}
bezierCurveTo : Point -> Point -> Point -> PathSegment
bezierCurveTo controlPoint1 controlPoint2 point =
    BezierCurveTo controlPoint1 controlPoint2 point


{-| Connects the last point in the previous shape to the x, y coordinates with a
straight line.

    lineTo ( x, y )

If you want to make a line independently of where the previous shape ended, you
can use `moveTo` before using lineTo.

-}
lineTo : Point -> PathSegment
lineTo point =
    LineTo point


{-| `moveTo` doesn't necessarily produce any shape, but it moves the starting
point somewhere so that you can use this with other lines.

    moveTo point

-}
moveTo : Point -> PathSegment
moveTo point =
    MoveTo point


{-| Adds a quadratic Bézier curve to the path. It requires two points. The
first point is a control point and the second one is the end point. The starting
point is the last point in the current path, which can be changed using `moveTo`
before creating the quadratic Bézier curve. Learn more about quadratic bezier
curves in the [MDN docs](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/quadraticCurveTo)

    quadraticCurveTo controlPoint point

    quadraticCurveTo ( cpx, cpy ) ( x, y )

  - `cpx`
      - The x axis of the coordinate for the control point.
  - `cpy`
      - The y axis of the coordinate for the control point.
  - `x`
      - The x axis of the coordinate for the end point.
  - `y`
      - The y axis of the coordinate for the end point.

-}
quadraticCurveTo : Point -> Point -> PathSegment
quadraticCurveTo controlPoint point =
    QuadraticCurveTo controlPoint point



-- Text drawables


{-| We use `text` to render text on the canvas. We need to pass the list of
settings to style it, the point with the coordinates where we want to render,
and the text to render.

Keep in mind that `align` and other settings can change where the text is
positioned with regards to the coordinates provided.

    Canvas.toHtml ( width, height )
        []
        [ text
            [ font { style = "", size = 48, family = "sans-serif" }, align Center ]
            ( 50, 50 )
            "Hello world"
        ]

You can learn more about drawing text and its settings in the **Drawing text**
section.

-}
text : List Setting -> Point -> String -> Renderable
text settings point str =
    addSettingsToRenderable settings
        (Renderable
            { commands = []
            , drawOp = NotSpecified
            , drawable = DrawableText { maxWidth = Nothing, point = point, text = str, autoSwap = Oneline }
            }
        )



-- Textures


{-| Draw a texture into your canvas.

Textures can be loaded by using `toHtmlWith` and passing in a `Texture.Source`.
Once the texture is loaded, and you have an actual `Texture`, you can use it
with this method to draw it.

You can also make different types of textures from the same texture, in case you
have a big sprite sheet and want to create smaller textures that are
a _viewport_ into a bigger sheet.

See the `Canvas.Texture` module and the `sprite` function in it.

-}
texture : List Setting -> Point -> Texture -> Renderable
texture settings p t =
    addSettingsToRenderable settings
        (Renderable
            { commands = []
            , drawOp = NotSpecified
            , drawable = DrawableTexture p t
            }
        )



-- Groups


{-| Groups many renderables into one, and provides the opportunity to apply
settings for the whole group.

    Canvas.toHtml ( width, height )
        []
        [ group [ fill Color.red ]
            [ shapes [] [ rect ( 0, 0 ) w h ]
            , text
                [ font { style = "", size = 48, family = "sans-serif" }, align Center ]
                ( 50, 50 )
                "Hello world"
            ]
        ]

-}
group : List Setting -> List Renderable -> Renderable
group settings entities =
    addSettingsToRenderable settings
        (Renderable
            { commands = []
            , drawOp = NotSpecified
            , drawable = DrawableGroup entities
            }
        )


{-| Empty renderable. Useful for creating an empty renderable instead of writing `group [] []`
-}
empty : Renderable
empty =
    Renderable
        { commands = []
        , drawOp = NotSpecified
        , drawable = DrawableEmpty
        }



-- Rendering internals


render : List Renderable -> List CanvasValue -> Commands
render entities cvalues =
    List.foldl (renderOne NotSpecified cvalues) CE.empty entities


renderOne : DrawOp -> List CanvasValue -> Renderable -> Commands -> Commands
renderOne parentDrawOp cvalues (Renderable { commands, drawable, drawOp }) cmds =
    cmds
        |> (::) CE.save
        |> (++) commands
        |> renderDrawable drawable (mergeDrawOp parentDrawOp drawOp) cvalues
        |> (::) CE.restore


renderDrawable : Drawable -> DrawOp -> List CanvasValue -> Commands -> Commands
renderDrawable drawable drawOp cvalues cmds =
    case drawable of
        DrawableText txt ->
            renderText drawOp txt cvalues cmds

        DrawableShapes ss ->
            List.foldl Path.renderShape (CE.beginPath :: cmds) ss
                |> renderShapeDrawOp drawOp

        DrawableTexture p t ->
            renderTexture p t cmds

        DrawableClear p w h ->
            renderClear p w h cmds

        DrawableGroup renderables ->
            renderGroup drawOp cvalues renderables cmds

        DrawableEmpty ->
            cmds


renderText : DrawOp -> Text -> List CanvasValue -> Commands -> Commands
renderText drawOp txt cvalues cmds =
    case txt.autoSwap of
        Oneline ->
            renderSingleText drawOp txt cmds

        Manual x ->
            renderTextwithNewline drawOp txt x cmds

        Letter { label, lineWidth, lineSpace } ->
            renderTextSwapwithInput drawOp cvalues True ( label, lineWidth, lineSpace ) txt cmds

        Word { label, lineWidth, lineSpace } ->
            renderTextSwapwithInput drawOp cvalues False ( label, lineWidth, lineSpace ) txt cmds


renderTextSwapwithInput : DrawOp -> List CanvasValue -> Bool -> ( String, Float, Float ) -> Text -> Commands -> Commands
renderTextSwapwithInput drawOp cvalues isLetter ( label, lWidth, lSpace ) txt cmds =
    let
        textVs =
            List.filter
                (\value -> value.label == label)
                cvalues

        textMatricsVs =
            List.map (\cvalue -> cvalue.value) <|
                List.filter
                    (\value -> value.valuetype == "TextMetrics")
                    textVs

        textStoredVs =
            List.map (\cvalue -> cvalue.value) <|
                List.filter
                    (\value -> value.valuetype == "storeValue")
                    textVs
    in
    renderTextSwap drawOp textMatricsVs textStoredVs isLetter ( label, lWidth, lSpace ) txt cmds


renderTextSwap : DrawOp -> List E.Value -> List E.Value -> Bool -> ( String, Float, Float ) -> Text -> Commands -> Commands
renderTextSwap drawOp textMatricsls storedValuels isLetter ( label, lWidth, lSpace ) txt cmds =
    let
        decodeUsage : E.Value -> Result D.Error String
        decodeUsage singleSV =
            D.decodeValue (D.field "usage" D.string) singleSV

        textSwapsls =
            List.filter (\x -> decodeUsage x == Ok "textSwap") storedValuels

        toWordls : String -> List String
        toWordls str =
            List.filter (\x -> x /= "") <| List.intersperse " " <| String.split " " str

        txtls =
            if isLetter then
                List.map String.fromChar <| String.toList txt.text

            else
                toWordls txt.text
    in
    if List.isEmpty textSwapsls then
        storeSwapValue txt.text txt.text label
            :: (List.map (CE.measureText label) <|
                    txtls
               )
            ++ cmds

    else
        let
            ( resotxt, resctxt ) =
                ( D.decodeValue (D.field "originText" D.string) <| Maybe.withDefault E.null <| List.head textSwapsls
                , D.decodeValue (D.field "changedText" D.string) <| Maybe.withDefault E.null <| List.head textSwapsls
                )
        in
        case ( resotxt, resctxt ) of
            ( Ok otxt, Ok ctxt ) ->
                if not (List.isEmpty textMatricsls) then
                    let
                        twidthls =
                            List.filterMap Result.toMaybe <|
                                List.map (D.decodeValue (D.field "width" D.float)) textMatricsls

                        genNewtxt : Float -> Float -> List Float -> Bool -> String -> String -> String
                        genNewtxt lwidth swidth mwidthls isLtr ipttxt opttxt =
                            case mwidthls of
                                mwidth :: restls ->
                                    if String.left 1 ipttxt == "\n" then
                                        let
                                            ( space, nipttxt ) =
                                                removeSpace 0 (String.dropLeft 1 ipttxt)

                                            droppedls =
                                                List.drop space restls
                                        in
                                        genNewtxt lwidth 0 droppedls isLtr nipttxt <| opttxt ++ "\n"

                                    else if mwidth >= lwidth then
                                        opttxt ++ ""

                                    else if mwidth + swidth >= lwidth then
                                        let
                                            ( space, nipttxt ) =
                                                removeSpace 0 ipttxt

                                            droppedls =
                                                List.drop space mwidthls
                                        in
                                        genNewtxt lwidth 0 droppedls isLtr nipttxt <| opttxt ++ "\n"

                                    else
                                        let
                                            addtxt =
                                                if isLtr then
                                                    String.left 1 ipttxt

                                                else
                                                    Maybe.withDefault "" <| List.head <| toWordls ipttxt

                                            nipttxt =
                                                if isLtr then
                                                    String.dropLeft 1 ipttxt

                                                else
                                                    String.concat <| List.drop 1 <| toWordls ipttxt
                                        in
                                        genNewtxt lwidth (mwidth + swidth) restls isLtr nipttxt <|
                                            opttxt
                                                ++ addtxt

                                [] ->
                                    opttxt

                        realtext =
                            genNewtxt lWidth 0 twidthls isLetter txt.text ""
                    in
                    renderTextwithNewline drawOp { txt | text = realtext } lSpace <|
                        storeSwapValue otxt realtext label
                            :: cmds

                else if txt.text == otxt then
                    renderTextwithNewline drawOp { txt | text = ctxt } lSpace <|
                        storeSwapValue otxt ctxt label
                            :: cmds

                else
                    storeSwapValue txt.text txt.text label
                        :: (List.map (CE.measureText label) <|
                                txtls
                           )
                        ++ cmds

            _ ->
                cmds


renderTextwithNewline : DrawOp -> Text -> Float -> Commands -> Commands
renderTextwithNewline drawOp txt lineSpace cmds =
    Tuple.second <|
        List.foldl
            (\t ( ( x, y ), cs ) ->
                ( ( x, y + lineSpace ), renderSingleText drawOp { txt | text = t, point = ( x, y ) } cs )
            )
            ( txt.point, cmds )
            (String.lines txt.text)


removeSpace : Int -> String -> ( Int, String )
removeSpace count txt =
    case String.left 1 txt of
        " " ->
            removeSpace (count + 1) <|
                String.dropLeft 1 txt

        _ ->
            ( count, txt )


storeSwapValue : String -> String -> String -> Command
storeSwapValue originText changedText label =
    CE.store label <|
        E.object [ ( "originText", E.string originText ), ( "changedText", E.string changedText ), ( "usage", E.string "textSwap" ) ]


renderSingleText : DrawOp -> Text -> Commands -> Commands
renderSingleText drawOp txt cmds =
    cmds
        |> renderTextDrawOp drawOp txt


renderTextDrawOp : DrawOp -> Text -> Commands -> Commands
renderTextDrawOp drawOp txt cmds =
    let
        ( x, y ) =
            txt.point
    in
    case drawOp of
        NotSpecified ->
            cmds
                |> renderTextFill txt x y Nothing
                |> renderTextStroke txt x y Nothing

        Fill fill ->
            renderTextFill txt x y (Just fill) cmds

        Stroke stroke ->
            renderTextStroke txt x y (Just stroke) cmds

        FillAndStroke fill stroke ->
            cmds
                |> renderTextFill txt x y (Just fill)
                |> renderTextStroke txt x y (Just stroke)


renderTextFill : Text -> Float -> Float -> Maybe CE.Style -> Commands -> Commands
renderTextFill txt x y maybeStyle cmds =
    CE.fillText txt.text x y txt.maxWidth
        :: (case maybeStyle of
                Just style ->
                    CE.fillStyleEx style :: cmds

                Nothing ->
                    cmds
           )


renderTextStroke : Text -> Float -> Float -> Maybe CE.Style -> Commands -> Commands
renderTextStroke txt x y maybeStyle cmds =
    CE.strokeText txt.text x y txt.maxWidth
        :: (case maybeStyle of
                Just style ->
                    CE.strokeStyleEx style :: cmds

                Nothing ->
                    cmds
           )


renderShapeDrawOp : DrawOp -> Commands -> Commands
renderShapeDrawOp drawOp cmds =
    case drawOp of
        NotSpecified ->
            cmds
                |> renderShapeFill Nothing
                |> renderShapeStroke Nothing

        Fill c ->
            renderShapeFill (Just c) cmds

        Stroke c ->
            renderShapeStroke (Just c) cmds

        FillAndStroke fc sc ->
            cmds
                |> renderShapeFill (Just fc)
                |> renderShapeStroke (Just sc)


renderShapeFill : Maybe CE.Style -> Commands -> Commands
renderShapeFill maybeStyle cmds =
    CE.fill CE.NonZero
        :: (case maybeStyle of
                Just style ->
                    CE.fillStyleEx style :: cmds

                Nothing ->
                    cmds
           )


renderShapeStroke : Maybe CE.Style -> Commands -> Commands
renderShapeStroke maybeStyle cmds =
    CE.stroke
        :: (case maybeStyle of
                Just style ->
                    CE.strokeStyleEx style :: cmds

                Nothing ->
                    cmds
           )


renderTexture : Point -> Texture -> Commands -> Commands
renderTexture ( x, y ) t cmds =
    T.drawTexture x y t cmds


renderTextureSource : Texture.Source msg -> ( String, Html msg )
renderTextureSource textureSource =
    case textureSource of
        T.TSImageUrl url onLoad ->
            ( url
            , img
                [ src url
                , attribute "crossorigin" "anonymous"
                , style "display" "none"
                , on "load" (D.map onLoad T.decodeImageLoadEvent)
                , on "error" (D.succeed (onLoad Nothing))
                ]
                []
            )


renderClear : Point -> Float -> Float -> Commands -> Commands
renderClear ( x, y ) w h cmds =
    CE.clearRect x y w h :: cmds


renderGroup : DrawOp -> List CanvasValue -> List Renderable -> Commands -> Commands
renderGroup drawOp cvalues renderables cmds =
    let
        cmdsWithDraw =
            case drawOp of
                NotSpecified ->
                    cmds

                Fill fill ->
                    CE.fillStyleEx fill :: cmds

                Stroke stroke ->
                    CE.strokeStyleEx stroke :: cmds

                FillAndStroke fc sc ->
                    CE.fillStyleEx fc :: CE.strokeStyleEx sc :: cmds
    in
    List.foldl (renderOne drawOp cvalues) cmdsWithDraw renderables
