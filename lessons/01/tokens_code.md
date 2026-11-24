## RU
```
Функция СкопироватьРекурсивно(Источник) Экспорт
	
	Перем Приемник;
	
	ТипИсточника = ТипЗнч(Источник);
	
#Если Сервер Или ТолстыйКлиентОбычноеПриложение Или ВнешнееСоединение Тогда
	Если ТипИсточника = Тип("ТаблицаЗначений") Тогда
		Возврат Источник.Скопировать();
	КонецЕсли;
#КонецЕсли	
	Если ТипИсточника = Тип("Структура") Тогда
		Приемник = СкопироватьСтруктуру(Источник);
	ИначеЕсли ТипИсточника = Тип("Соответствие") Тогда
		Приемник = СкопироватьСоответствие(Источник);
	ИначеЕсли ТипИсточника = Тип("Массив") Тогда
		Приемник = СкопироватьМассив(Источник);
	ИначеЕсли ТипИсточника = Тип("СписокЗначений") Тогда
		Приемник = СкопироватьСписокЗначений(Источник);
	Иначе
		Приемник = Источник;
	КонецЕсли;
	
	Возврат Приемник;
	
КонецФункции
```
## EN
```
Function CopyRecursive(Source) Export
	
	Var Receiver;
	
	SourceType = TypeOf(Source);
	
#If Server Or ThickClientOrdinaryApplication Or ExternalConnection Then
	If SourceType = Type("ValueTable") Then
		Return Source.Copy();
	EndIf;
#EndIf	
	If SourceType = Type("Structure") Then
		Receiver = CopyStructure(Source);
	ElsIf SourceType = Type("Map") Then
		Receiver = CopyMap(Source);
	ElsIf SourceType = Type("Array") Then
		Receiver = CopyArray(Source);
	ElsIf SourceType = Type("ValueList") Then
		Receiver = CopyValueList(Source);
	Else
		Receiver = Source;
	EndIf;
	
	Return Receiver;
	
EndFunction
```