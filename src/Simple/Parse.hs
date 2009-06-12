module Simple.Parse where

import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Char
import Simple.Ast

import Control.Applicative hiding ((<|>), many)
import Data.Char (isSpace)
import List


parsePrg :: String -> (Ast, EnvValue, FuncEnvValue)
parsePrg input =
    case parse program "" input of
      Left err -> error $ "Parser Error " ++ show err
      Right p -> p

program :: Parser (Ast, EnvValue, FuncEnvValue)
program = do {
            (ast, env, mainName) <- function;
            do {
              funcEnvValue <- functions;
              return (ast, env, (FuncEnv (Func "Main" ast env) funcEnvValue))
            }
            <|>
            do {
              return (ast, env, (FuncEnv (Func "Main" ast env) FuncEnd))
            }
          }

functions :: Parser FuncEnvValue
functions = do {
              --(ast, env, name) <- try(function);
              do{
                whiteSpace;
                try(string ",");
                (ast, env, name) <- try(function);
                funcEnvValue <- functions;
                return (FuncEnv (Func name ast env) funcEnvValue)
              }
              <|>
              do{
                return FuncEnd 
              }
            }

function :: Parser (Ast, EnvValue, String)
function = do {
             whiteSpace;
             name <- many1 letter; 
             whiteSpace;
             string "=>";
             whiteSpace;
             env <- constStart;
             ast <- op;
             return (ast, env, name)
           }
           
constStart :: Parser EnvValue
constStart = do{
               string "[";
               do
                 {
                   c <- try(consts);
                   string "]";
                   return c
                 }
               <|>
               do {
                 string "]";
                 return EnvEnd
               }
             }

consts :: Parser EnvValue
consts = do { 
           c <- Simple.Parse.const;
           do 
             {
               try(string ",");
               rest <- consts;
               return (Env c rest);
             } 
           <|> 
           do {
             return (Env c EnvEnd);
           }
         }
           
const :: Parser ConstValue
const = do 
  str <- many1 letter
  whiteSpace
  string "="
  whiteSpace
  value <- op
  return (Simple.Ast.Const str value)

whiteSpace :: Parser ()
whiteSpace = skipMany space

expr = zero_expr <|> succ_expr <|> parens op <|> Simple.Parse.lookup <|> call <|> op

call :: Parser Ast
call = do {
         whiteSpace;
         try(string "Call");
         whiteSpace;
         fktName <- try(many1 letter);
         whiteSpace;
         input <- op;
         return (Call fktName input)
       }

lookup :: Parser Ast
lookup = do {
           whiteSpace;
           try(string "Lookup");
           whiteSpace;
           look <- try(many1 letter);
           return (Lookup look)
         }

opTest sign = 
      do {whiteSpace;
          try(string sign);
          whiteSpace}

table = [[tableOp (opTest "*") mul_expr AssocLeft],
         [tableOp (opTest "+") (plus_expr) AssocLeft]] where 
           tableOp s f assoc = Infix (do {s; return f}) assoc 

op = buildExpressionParser table expr
     

parens :: Parser Ast -> Parser Ast
parens exp = do
    whiteSpace
    string "("
    whiteSpace
    e <- exp
    whiteSpace
    string ")"
    whiteSpace
    return e

zero_expr = do
    string "z"
    whiteSpace
    return Zero

succ_expr = do
    string "s"
    whiteSpace
    e <- op
    whiteSpace
    return (Succ e)

plus_expr e1 e2 = (Plus e1 e2)

mul_expr e1 e2 = (Mul e1 e2)