-- Abstract Syntax tree
module Twodee.Ast (Inface (..),
                   Outface (..),
                   Exp (..),
                   Command (..),
                   Mod (..),
                   Joint (..),
                   Wire,
                   width)
where

import qualified Data.Graph as Graph
import qualified Data.Set as Set
import Data.List
import Data.Maybe (fromJust)

import Data.Monoid

data Inface = N | W
  deriving Show

data Outface = S | E
  deriving Show

type Wire = Int

data Exp = Unit
         | Tuple Exp Exp
         | Inl   Exp
         | Inr   Exp
         | Iface Inface

instance Show Exp where
    show x =
        case x of
          Unit -> "()"
          Tuple e1 e2 -> mconcat ["(", show e1, ", ", show e2, ")"]
          Inl e -> mconcat ["inl ", show e]
          Inr e -> mconcat ["inr ", show e]
          Iface i -> show i

data Command = SendEmpty
             | Send1 Exp Outface
             | Send2 Exp Outface
                     Exp Outface
             | Case  Exp Outface Outface
             | Split Exp
             | Use   String

instance Show Command where
    show x =
        case x of
          SendEmpty -> "send[]"
          Send1 e o -> mconcat ["send[", show e, ", ", show o, "]"]
          Send2 e1 o1 e2 o2 -> mconcat ["send[",
                                        show e1, ", ", show o1, "]",
                                        "[", show e2, ", ", show o2, "]"]
          Case e1 o1 o2 -> mconcat ["case(", show e1, ", ", show o1,
                                                      ", ", show o2, ")"]
          Split e -> mconcat ["split(", show e, ")"]
          Use s -> mconcat ["use ", show s, ""]

data Joint = JBox { command :: Command,
                    north :: Wire,
                    east :: Wire,
                    south :: Wire,
                    west :: Wire }
           | JBox_Group { boxes :: [Joint],
                          b_north :: Wire,
                          b_south :: Wire,
                          b_east  :: Wire,
                          b_west  :: Wire }

-- Simplify the joints, removing the Groups
simplify_joint :: [Joint] -> [Joint]
simplify_joint ((JBox_Group boxes _ _ _ _) : rest) = simplified ++ (simplify_joint rest)
    where
      simplified = simplify_joint boxes
simplify_joint (b : rest) = [b] ++ (simplify_joint rest)
simplify_joint [] = []

data Mod = Module { mod_boxes :: [Joint],
                    name :: String,
                    input_north :: Wire,
                    input_west :: Wire,
                    output_east :: Wire }

findEdges :: [(Int, Joint)] -> [[(Int, Int)]]
findEdges [] = []
findEdges ((id, box) : rest) =
    let
        getOutEdges bx = Set.fromList [south bx, west bx]
        getInEdges bx = Set.fromList [north bx, east bx]
        s = getOutEdges box
        matches boxes = fil boxsets
            where boxsets = fmap (\(id, b) -> (id, getInEdges b)) boxes
                  fil :: [(Int, Set.Set Int)] -> [Int]
                  fil [] = []
                  fil ((tid, bs) : r) = if Set.intersection s bs /= Set.empty
                                        then tid : (fil r)
                                        else fil r
    in
      ([(id, tid) | tid <- matches rest] : findEdges rest)

order [] numbered = []
order (v : vs) numbered =
    case lookup v numbered of
      Just b -> b : (order vs numbered)

topsort jnts =
    let
        numbered = zip [1..] jnts
        bnds = (1, length numbered)
        edges = findEdges numbered
        vertices = Graph.topSort $ Graph.buildG bnds $ mconcat edges
    in
      order vertices numbered

data WireInfo = PassThrough Int
              | End_W Int
              | End_N Int
              | Start_E Int
              | Start_S Int
  deriving (Eq, Ord)

data ExplicitOrder = EOB { contents :: Command,
                           wires :: [WireInfo],
                           live :: [(Wire, Int)] }
                   | EOM { wires :: [WireInfo],
                           mod_name :: String }

process_box :: Joint -> ExplicitOrder
process_box box = EOB { contents = command box,
                        wires = wi,
                        live = [] }
    where
      wi = [End_W $ west box,
            End_N $ north box,
            Start_E $ east box,
            Start_S $ south box]

explicit_wiring :: [Joint] -> [ExplicitOrder]
explicit_wiring jnts = fmap process_box ordered
  where
    ordered = topsort jnts

update_liveness genset killset liveelements =
    let
        remove [] es = es
        remove (e : rest) es = filter (\(w, _) -> w /= e) es
        max_num = foldl1 max $ fmap snd liveelements
        add n [] es = es
        add n (e : rest) es = add (n+1) rest ((e, n+1) : es)
    in
      ((add max_num genset) . (remove killset)) liveelements


liveness_analyze :: [(Wire, Int)] -> [ExplicitOrder] -> [ExplicitOrder]
liveness_analyze l [] = []
liveness_analyze l (b : rest) = b {live = updated_live } : (liveness_analyze updated_live rest)
    where
      find_gen [] = []
      find_gen (e : es) =
          case e of
            Start_E i -> i : (find_gen es)
            Start_S i -> i : (find_gen es)
            _ -> find_gen es
      find_kill [] = []
      find_kill (e : es) =
          case e of
            End_W i -> i : (find_kill es)
            End_N i -> i : (find_kill es)
            _ -> find_kill es
      gen = find_gen $ wires b
      kill = find_kill $ wires b
      updated_live = update_liveness gen kill l


instance Show Joint where
    show b =
        show $ (command b)

width :: Joint -> Int
width c = length $ show $ command c

hRule corner line w = mconcat [corner, take (w-2) $ repeat line, corner]
boxRule = hRule "*" '='
modRule = hRule "," '.'

sorround :: String -> String -> String
sorround elem str = mconcat [elem, str, elem]

crate_width :: Bool -> Command -> Int
crate_width west_input command = length $ show command

build = intersperse "\n"

has_north_input crate = case find (\e -> case e of
                                      End_N _ -> True
                                      _ -> False) $ wires crate of
                          Nothing -> False
                          Just _ -> True

has_south_output crate = case find (\e -> case e of
                                       Start_S _ -> True
                                       _ -> False) $ wires crate of
                           Nothing -> False
                           Just _ -> True

has_east_output crate = case find (\e -> case e of
                                      Start_E _ -> True
                                      _ -> False) $ wires crate of
                          Nothing -> False
                          Just _ -> True

has_west_input crate = case find (\e -> case e of
                                     End_W _ -> True
                                     _ -> False) $ wires crate of
                         Nothing -> False
                         Just _ -> True

fillline char k = mconcat $ take k (repeat char)
spaces = fillline " "

boxhrule = fillline "="
wireline = fillline "-"

line1 :: Bool -> Int -> String
line1 n cw = mconcat ["    ", if n then "++" else "  ", spaces (cw+2)]

line2 :: Bool -> Int -> String
line2 n cw = mconcat ["   ", if n then "++v" else "   ", spaces (cw+2)]

line3 :: Bool -> Int -> String
line3 n cw = mconcat ["  ", if n then "++*" else "  *", boxhrule cw,
                      "*  "]

line4 :: Bool -> Bool -> Bool -> Command -> String
line4 n e w c = mconcat [if e then "+" else " ",
                         if e then
                             if n then "#" else "-"
                         else " ",
                         ">!", show c, "!",
                         if w then "-+" else "  "]

line5 :: Bool -> Bool -> Bool -> Int -> String
line5 n e w cw = mconcat [if e then "|" else " ",
                         if n then "|" else " ",
                         " ",
                         "*", boxhrule cw, "* ",
                         if w then "|" else " "]

line6 :: Bool -> Bool -> Bool -> Bool -> Int -> String
line6 n e w s cw = mconcat [if e then "|" else " ",
                            if n then "|" else " ",
                            "  ", spaces (cw-1),
                            if s then "+-+" else "   ",
                            if w then "|" else " "]



create_box_hrule_lower wi ni eo cw =
    mconcat [if wi then "|" else " ",
             if ni then "|*" else " *",
             mconcat $ take (cw-6) (repeat " "),
             if eo then "*|" else "* "]

create_box_contents wi ni eo c =
    mconcat [if wi then
                 if ni
                 then "+#>!"
                 else "+->!"
             else "   !", show c, "!",
             if eo then "+" else " "]

create_box_south_output ni wi eo so cw = ""

listflip = fmap (\(x, y) -> (y, x))

wirejoin [] p = []
wirejoin (w : rest) p =
    let
        wnum = case w of
                 PassThrough n -> n
                 Start_E n -> n
                 Start_S n -> n
                 End_W n -> n
                 End_N n -> n
        pos = fromJust $ lookup wnum p
    in
      (w, pos) : (wirejoin rest p)

create_lines :: Int -> [WireInfo] -> [(Wire, Int)] -> Bool -> Bool -> Bool -> Bool -> [String]
create_lines cw wires p n e w s =
    let
        ordered_wires = sort $ listflip (wirejoin wires p)
        process_wire [] _ _ _ _ accum = reverse accum
        process_wire (wire : rest) n e w s accum =
            case snd wire of
              PassThrough k -> process_wire rest n e w s (line : accum)
                  where
                    line = mconcat [if w then "#" else " ",
                                    if n then "#" else " ",
                                    wireline (cw + 3),
                                    if s then "#" else " ",
                                    if e then "#" else " "]
              End_W k -> process_wire rest n e False s (line : accum)
                  where
                    line = mconcat ["+", if n then "|" else " ",
                                    spaces (cw+3),
                                    if s then "|" else " ",
                                    if e then "|" else " "]
              Start_S k -> process_wire rest n e w False (line : accum)
                  where
                    line = mconcat [if w then "|" else " ",
                                    if n then "|" else " ",
                                    spaces (cw+3),
                                    "+",
                                    if e then "#" else "-"]
              Start_E k -> process_wire rest n False w s (line : accum)
                  where
                    line = mconcat [if w then "|" else " ",
                                    if n then "|" else " ",
                                    spaces (cw+3),
                                    if s then "|" else " ",
                                    "+"]
              End_N k -> process_wire rest False e w s (line : accum)
                  where
                    line = mconcat [if w then "#" else "-",
                                    "+",
                                    spaces (cw+3),
                                    if s then "|" else " ",
                                    if e then "|" else " "]
    in
      process_wire ordered_wires n e w s []

renderbox :: ExplicitOrder -> [String]
renderbox crate =
    let
        n = has_north_input crate
        w = has_west_input crate
        e = has_east_output crate
        s = has_south_output crate
        cw = crate_width w (ctnts)
        ctnts = contents crate
        circuitry = wires crate
        positions = live crate
    in
      [line1 n cw,
       line2 n cw,
       line3 n cw,
       line4 n e w ctnts,
       line5 n e w cw,
       line6 n e w s cw] ++
      create_lines cw circuitry positions n e w s

render_eo :: [ExplicitOrder] -> [String]
render_eo boxes = join $ fmap renderbox analyzed_boxes
    where analyzed_boxes = liveness_analyze [] boxes
          join x = fmap mconcat $ transpose x

create_module_boxes :: String -> Wire -> Wire -> Wire -> [ExplicitOrder]
create_module_boxes name inp_n inp_w out_e = []

render_module :: Mod -> String
render_module (Module bxs name inp_n inp_w out_e) =
{-
  First, we should build up the correct ExplicitOrder with Fake boxes for the module.
  Then we should call the render_eo function which also liveness analyzes. It should
    output the information we need to render the module itself
  Then we must gather the width and height of the module to output it correctly
 -}
    let
        joints = simplify_joint bxs
        module_boxes = create_module_boxes name inp_n inp_w out_e
        eobs = explicit_wiring joints
        rendered = render_eo (eobs ++ module_boxes)
        boxes = ""
    in
      boxes

instance Show Mod where
    show m = render_module m

render :: [Mod] -> String -> String
render modules stdlib = mconcat [rendered_mods, stdlib]
  where rendered_mods = mconcat $ fmap show modules
